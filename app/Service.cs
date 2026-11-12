// Discord WARP v2 - Windows service "DiscordWARP" (runs as LocalSystem; needed for the TUN adapter and NRPT).
// - starts mihomo with %ProgramData%\DiscordWARP\engine\config.yaml and restarts it if it exits
// - keeps the NRPT rule (Discord names -> 198.18.0.2) in place, removes it while paused
// - self-heal: every 2 min checks the Discord API through WARP; 3 failed rounds in a row and no active call
//   -> recreate the tunnel (restart mihomo), at most 3 times per hour
// - custom controls from the app: 128 restart engine, 129 pause, 130 resume
using System;
using System.Diagnostics;
using System.IO;
using System.ServiceProcess;
using System.Text;
using System.Threading;

namespace DiscordWarp
{
    public class EngineService : ServiceBase
    {
        static string LogFile { get { return Path.Combine(Paths.LogDir, "service.log"); } }
        static string EngineLog { get { return Path.Combine(Paths.LogDir, "engine.log"); } }
        static readonly string[] NrptDomains = { "discord.com", "discordapp.com", "discordapp.net", "discord.gg", "discord.media", "discordcdn.com",
                                                 "discordstatus.com", "discord.co", "discord.dev", "discord.gift", "discord.new", "dis.gd" };
        readonly object gate = new object();
        Process engine;
        volatile bool stopping, userStop;
        Timer monitor;
        int failedRounds, restartsThisHour; DateTime hourStart = DateTime.Now;

        public EngineService() { ServiceName = Paths.ServiceName; CanStop = true; CanShutdown = true; AutoLog = false; }

        static void L(string m) { Log.Write(LogFile, m); }

        protected override void OnStart(string[] args)
        {
            L("=== service start (v" + ReadVersion() + ")");
            ThreadPool.QueueUserWorkItem(_ =>
            {
                if (File.Exists(Paths.PausedFlag)) { L("paused by the user - engine not started"); SetNrpt(false); return; }
                SetNrpt(true);
                StartEngine();
            });
            monitor = new Timer(_ => Monitor(), null, TimeSpan.FromMinutes(2), TimeSpan.FromMinutes(2));
        }

        protected override void OnStop() { stopping = true; if (monitor != null) monitor.Dispose(); StopEngine("service stop"); L("=== service stop"); }
        protected override void OnShutdown() { OnStop(); }

        protected override void OnCustomCommand(int command)
        {
            ThreadPool.QueueUserWorkItem(_ =>
            {
                try
                {
                    if (command == Ctl.RestartEngine) { L("app: restart engine (repair)"); StopEngine("repair"); Thread.Sleep(1500); if (!File.Exists(Paths.PausedFlag)) StartEngine(); }
                    else if (command == Ctl.Pause) { L("app: pause"); File.WriteAllText(Paths.PausedFlag, DateTime.Now.ToString("o")); StopEngine("pause"); SetNrpt(false); }
                    else if (command == Ctl.Resume) { L("app: resume"); try { File.Delete(Paths.PausedFlag); } catch { } SetNrpt(true); StartEngine(); }
                }
                catch (Exception e) { L("custom command " + command + " failed: " + e.Message); }
            });
        }

        static string ReadVersion() { try { return File.ReadAllText(Paths.VersionFile).Trim(); } catch { return "?"; } }

        void StartEngine()
        {
            lock (gate)
            {
                if (engine != null && !engine.HasExited) return;
                userStop = false;
                foreach (var p in Process.GetProcessesByName("mihomo")) { try { p.Kill(); } catch { } }   // never two engines with the same WARP key
                var psi = new ProcessStartInfo(Paths.MihomoExe, "-d \"" + Paths.EngineDir + "\" -f \"" + Path.Combine(Paths.EngineDir, "config.yaml") + "\"")
                { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true, WorkingDirectory = Paths.EngineDir };
                engine = new Process { StartInfo = psi, EnableRaisingEvents = true };
                engine.OutputDataReceived += (s, e) => { if (e.Data != null) Log.Write(EngineLog, e.Data); };
                engine.ErrorDataReceived += (s, e) => { if (e.Data != null) Log.Write(EngineLog, e.Data); };
                engine.Exited += OnEngineExited;
                engine.Start(); engine.BeginOutputReadLine(); engine.BeginErrorReadLine();
                L("engine started pid " + engine.Id);
            }
        }

        void StopEngine(string why)
        {
            lock (gate)
            {
                userStop = true;
                if (engine != null && !engine.HasExited) { try { engine.Kill(); engine.WaitForExit(5000); } catch { } L("engine stopped (" + why + ")"); }
                engine = null;
            }
        }

        int crashCount; DateTime lastCrash = DateTime.MinValue;
        void OnEngineExited(object sender, EventArgs e)
        {
            if (stopping || userStop) return;
            var p = sender as Process; int code = -1; try { code = p.ExitCode; } catch { }
            crashCount = (DateTime.Now - lastCrash).TotalMinutes < 10 ? crashCount + 1 : 1; lastCrash = DateTime.Now;
            int wait = Math.Min(60, 5 * crashCount);
            L("engine exited unexpectedly (code " + code + "), restart in " + wait + " s");
            ThreadPool.QueueUserWorkItem(_ => { Thread.Sleep(wait * 1000); if (!stopping && !File.Exists(Paths.PausedFlag)) { lock (gate) engine = null; StartEngine(); } });
        }

        void Monitor()
        {
            try
            {
                if (stopping || File.Exists(Paths.PausedFlag) || engine == null || engine.HasExited) { failedRounds = 0; return; }
                int good = 0; var sb = new StringBuilder();
                for (int i = 0; i < 4; i++) { int d = Mihomo.DiscordDelay(3000); sb.Append(d < 0 ? "fail" : d.ToString()).Append(i < 3 ? "," : ""); if (d >= 0 && d < 300) good++; Thread.Sleep(2000); }
                if (good >= 3) { if (failedRounds > 0) L("check OK again: " + sb); failedRounds = 0; return; }
                failedRounds++;
                L("check round failed (" + failedRounds + "/3): " + sb);
                if (failedRounds < 3) return;
                failedRounds = 0;
                if ((DateTime.Now - hourStart).TotalHours >= 1) { hourStart = DateTime.Now; restartsThisHour = 0; }
                if (restartsThisHour >= 3) { L("self-heal: limit of 3 restarts per hour reached - waiting"); return; }
                if (Mihomo.DiscordInCall()) { L("self-heal: Discord call active - not restarting"); return; }
                restartsThisHour++;
                L("self-heal: recreating the WARP tunnel (restart " + restartsThisHour + "/3 this hour)");
                StopEngine("self-heal"); Thread.Sleep(1500); StartEngine();
            }
            catch (Exception e) { L("monitor error: " + e.Message); }
        }

        /// <summary>NRPT: only Discord's names are resolved by the engine (198.18.0.2); everything else keeps the normal DNS.</summary>
        static void SetNrpt(bool on)
        {
            var sb = new StringBuilder("$r = Get-DnsClientNrptRule | Where-Object Comment -eq 'DiscordWARP'; ");
            if (on)
            {
                var ns = new StringBuilder();
                foreach (var d in NrptDomains) ns.Append("'" + d + "','." + d + "',");
                ns.Append("'discord-attachments-uploads-prd.storage.googleapis.com'");
                sb.Append("if (-not $r) { Add-DnsClientNrptRule -Namespace @(" + ns + ") -NameServers '198.18.0.2' -Comment 'DiscordWARP' -DisplayName 'Discord via WARP' | Out-Null; 'added' } else { 'present' }; Clear-DnsClientCache");
            }
            else sb.Append("$r | ForEach-Object { Remove-DnsClientNrptRule -Name $_.Name -Force }; Clear-DnsClientCache; 'removed'");
            try
            {
                var psi = new ProcessStartInfo("powershell.exe", "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command \"" + sb.ToString().Replace("\"", "\\\"") + "\"")
                { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
                using (var p = Process.Start(psi)) { var o = p.StandardOutput.ReadToEnd().Trim(); var e = p.StandardError.ReadToEnd().Trim(); p.WaitForExit(30000); L("NRPT " + (on ? "on" : "off") + ": " + o + (e.Length > 0 ? " ERR " + e : "")); }
            }
            catch (Exception e) { L("NRPT failed: " + e.Message); }
        }
    }
}
