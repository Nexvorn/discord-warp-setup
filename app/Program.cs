// Discord WARP v2 - entry point.
//   DiscordWARP.exe              open the window (+ tray icon)
//   DiscordWARP.exe --tray       start hidden next to the clock (used at logon)
//   DiscordWARP.exe --autoinstall  (package folder) start installing right away (used by the updater)
//   DiscordWARP.exe --service    run as the Windows service (started by the Service Control Manager)
//   DiscordWARP.exe --selftest   build the UI without showing it, read the status, print results, exit
using System;
using System.IO;
using System.Linq;
using System.ServiceProcess;
using System.Threading;
using System.Windows.Markup;

namespace DiscordWarp
{
    static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            var a = args.Select(x => x.ToLowerInvariant()).ToArray();
            if (a.Contains("--service")) { ServiceBase.Run(new EngineService()); return 0; }
            AppDomain.CurrentDomain.UnhandledException += (s, e) => MainApp.L("CRASH: " + e.ExceptionObject);
            if (a.Contains("--selftest")) return SelfTest();

            var exeDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
            bool package = File.Exists(Path.Combine(exeDir, @"setup\Install.ps1")) && !string.Equals(exeDir, Paths.InstallDir, StringComparison.OrdinalIgnoreCase);
            var name = package ? @"Local\DiscordWARP-Setup" : @"Local\DiscordWARP-App";
            bool created;
            using (var mutex = new Mutex(true, name, out created))
            using (var show = new EventWaitHandle(false, EventResetMode.AutoReset, name + "-Show"))
            {
                if (!created) { show.Set(); return 0; }   // already running: bring that window to the front
                MainApp.L("start " + string.Join(" ", args));
                new MainApp(a.Contains("--tray"), a.Contains("--autoinstall")).Run(show);
                MainApp.L("exit");
            }
            return 0;
        }

        static int SelfTest()
        {
            try
            {
                var t = typeof(MainApp).GetField("MainXaml", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static);
                var w = (System.Windows.Window)XamlReader.Parse((string)t.GetValue(null));
                int found = new[] { "Ver", "Dot", "StatusTitle", "StatusSub", "BtnInstall", "Actions", "BtnDiscord", "BtnCheck", "BtnRepair", "BtnPause", "BtnUpdate", "BtnReport", "BtnUninstall", "ListTitle", "ListPanel", "Busy", "Foot" }.Count(n => w.FindName(n) != null);
                Console.WriteLine("ui controls found: " + found + "/17");
                var st = Status.Read(true);
                Console.WriteLine("status: installed=" + st.Installed + " paused=" + st.Paused + " service=" + st.ServiceRunning + " engine=" + st.EngineRunning + " tun=" + st.TunUp + " nrpt=" + st.Nrpt + " delay=" + st.Delay + " version=" + st.Version);
                return 0;
            }
            catch (Exception e) { Console.WriteLine("SELFTEST FAILED: " + e); return 1; }
        }
    }
}
