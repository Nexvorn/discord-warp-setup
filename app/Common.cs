// Discord WARP v2 - shared code (paths, logging, mihomo API over a named pipe, JSON, status).
// C# 5 / .NET Framework 4.8 (built into Windows 10/11), compiled with the csc.exe that ships with Windows.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Net.NetworkInformation;
using System.ServiceProcess;
using System.Text;
using System.Web.Script.Serialization;
using Microsoft.Win32;

namespace DiscordWarp
{
    public static class Paths
    {
        public const string ServiceName = "DiscordWARP";
        public const string PipeName = "discord-warp-mihomo";            // mihomo external-controller-pipe
        public const string TunDevice = "DiscordWARP";                   // TUN adapter name
        public const string Repo = "Nexvorn/discord-warp-setup";
        public static string InstallDir { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "DiscordWARP"); } }
        public static string DataDir { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "DiscordWARP"); } }
        public static string EngineDir { get { return Path.Combine(DataDir, "engine"); } }          // config.yaml (contains the WARP key; SYSTEM+Admins only)
        public static string LogDir { get { return Path.Combine(DataDir, "logs"); } }
        public static string PausedFlag { get { return Path.Combine(DataDir, "paused.flag"); } }
        public static string SecretFile { get { return Path.Combine(DataDir, "api-secret.txt"); } } // local API secret (users may read)
        public static string VersionFile { get { return Path.Combine(DataDir, "version.txt"); } }
        public static string UserDir { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DiscordWARP"); } }
        public static string MihomoExe { get { return Path.Combine(InstallDir, "mihomo.exe"); } }
        public static string DiscordUpdateExe { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Discord\Update.exe"); } }
    }

    public static class Log
    {
        static readonly object Gate = new object();
        public static void Write(string file, string msg)
        {
            try
            {
                lock (Gate)
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(file));
                    var fi = new FileInfo(file);
                    if (fi.Exists && fi.Length > 1024 * 1024) { File.Copy(file, file + ".old", true); File.Delete(file); }
                    File.AppendAllText(file, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " " + msg + Environment.NewLine, new UTF8Encoding(false));
                }
            }
            catch { }
        }
    }

    public static class Json
    {
        static readonly JavaScriptSerializer S = new JavaScriptSerializer { MaxJsonLength = 64 * 1024 * 1024 };
        public static Dictionary<string, object> Parse(string s)
        {
            try { return S.DeserializeObject(s) as Dictionary<string, object>; } catch { return null; }
        }
        public static object Get(Dictionary<string, object> d, string key)
        {
            object v; return d != null && d.TryGetValue(key, out v) ? v : null;
        }
    }

    /// <summary>mihomo REST API over its Windows named pipe (no TCP port is opened).</summary>
    public static class Mihomo
    {
        public static string ReadSecret()
        {
            try { return File.ReadAllText(Paths.SecretFile).Trim(); } catch { return ""; }
        }

        public static string Get(string apiPath, int timeoutMs)
        {
            using (var c = new NamedPipeClientStream(".", Paths.PipeName, PipeDirection.InOut))
            {
                c.Connect(Math.Min(timeoutMs, 3000));
                var req = "GET " + apiPath + " HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer " + ReadSecret() + "\r\nConnection: close\r\n\r\n";
                var b = Encoding.ASCII.GetBytes(req);
                c.Write(b, 0, b.Length); c.Flush();
                var ms = new MemoryStream(); var buf = new byte[16384]; int n;
                var sw = Stopwatch.StartNew();
                while ((n = c.Read(buf, 0, buf.Length)) > 0) { ms.Write(buf, 0, n); if (sw.ElapsedMilliseconds > timeoutMs + 3000) break; }
                var raw = Encoding.UTF8.GetString(ms.ToArray());
                int i = raw.IndexOf("\r\n\r\n", StringComparison.Ordinal);
                if (i < 0) return "";
                var head = raw.Substring(0, i); var body = raw.Substring(i + 4);
                if (head.IndexOf("Transfer-Encoding: chunked", StringComparison.OrdinalIgnoreCase) >= 0) body = Unchunk(body);
                return body;
            }
        }

        static string Unchunk(string body)
        {
            var sb = new StringBuilder(); int i = 0;
            while (i < body.Length)
            {
                int nl = body.IndexOf("\r\n", i, StringComparison.Ordinal); if (nl < 0) break;
                int len; if (!int.TryParse(body.Substring(i, nl - i).Trim(), System.Globalization.NumberStyles.HexNumber, null, out len) || len == 0) break;
                sb.Append(body, nl + 2, Math.Min(len, body.Length - nl - 2)); i = nl + 2 + len + 2;
            }
            return sb.ToString();
        }

        /// <summary>Delay through the WARP proxy to the Discord API, in ms; -1 = failed.</summary>
        public static int DiscordDelay(int timeoutMs)
        {
            try
            {
                var d = Json.Parse(Get("/proxies/WARP/delay?url=https%3A%2F%2Fdiscord.com%2Fapi%2Fv9%2Fgateway&timeout=" + timeoutMs, timeoutMs));
                var v = Json.Get(d, "delay");
                return v == null ? -1 : Convert.ToInt32(v);
            }
            catch { return -1; }
        }

        /// <summary>True while Discord has voice/video UDP flows to its media ranges (never restart during a call).</summary>
        public static bool DiscordInCall()
        {
            try
            {
                var d = Json.Parse(Get("/connections", 3000));
                var conns = Json.Get(d, "connections") as object[];
                if (conns == null) return false;
                foreach (var o in conns)
                {
                    var c = o as Dictionary<string, object>; var m = Json.Get(c, "metadata") as Dictionary<string, object>;
                    if (m == null) continue;
                    var proc = Convert.ToString(Json.Get(m, "process")); var net = Convert.ToString(Json.Get(m, "network"));
                    var dst = Convert.ToString(Json.Get(m, "destinationIP"));
                    if (string.Equals(proc, "Discord.exe", StringComparison.OrdinalIgnoreCase) && net == "udp" &&
                        (dst.StartsWith("104.28.") || dst.StartsWith("104.29.") || dst.StartsWith("66.22.") || dst.StartsWith("195.62.89.")))
                        return true;
                }
            }
            catch { }
            return false;
        }
    }

    public class Status
    {
        public bool Installed, Paused, ServiceRunning, EngineRunning, TunUp, Nrpt;
        public int Delay = -1;
        public string Version = "";

        public static Status Read(bool measure)
        {
            var s = new Status();
            try { s.Version = File.ReadAllText(Paths.VersionFile).Trim(); } catch { }
            ServiceController sc = null;
            try { sc = ServiceController.GetServices().FirstOrDefault(x => x.ServiceName == Paths.ServiceName); } catch { }
            s.Installed = sc != null;
            if (!s.Installed) return s;
            s.Paused = File.Exists(Paths.PausedFlag);
            try { s.ServiceRunning = sc.Status == ServiceControllerStatus.Running; } catch { }
            s.EngineRunning = Process.GetProcessesByName("mihomo").Length > 0;
            try { s.TunUp = NetworkInterface.GetAllNetworkInterfaces().Any(n => n.Name == Paths.TunDevice && n.OperationalStatus == OperationalStatus.Up); } catch { }
            s.Nrpt = NrptPresent();
            if (measure && s.EngineRunning && !s.Paused) s.Delay = Mihomo.DiscordDelay(5000);
            return s;
        }

        public static bool NrptPresent()
        {
            try
            {
                using (var k = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\Dnscache\Parameters\DnsPolicyConfig"))
                {
                    if (k == null) return false;
                    foreach (var n in k.GetSubKeyNames())
                        using (var r = k.OpenSubKey(n))
                            if (r != null && Convert.ToString(r.GetValue("Comment")) == "DiscordWARP") return true;
                }
            }
            catch { }
            return false;
        }
    }

    /// <summary>Custom service controls (the installer grants interactive users the right to send them).</summary>
    public static class Ctl
    {
        public const int RestartEngine = 128, Pause = 129, Resume = 130;
        public static void Send(int cmd)
        {
            using (var sc = new ServiceController(Paths.ServiceName)) sc.ExecuteCommand(cmd);
        }
    }
}
