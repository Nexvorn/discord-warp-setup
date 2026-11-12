// Discord WARP v2 - the desktop app: one window (Arabic, right-to-left) + tray icon.
// Installed mode: status, Discord button, full check, repair, pause/resume, update search, help report, uninstall.
// Package mode (started from the downloaded folder): "Install" button with a live list of the installer's steps.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;
using Forms = System.Windows.Forms;
using Drawing = System.Drawing;

namespace DiscordWarp
{
    public class MainApp
    {
        const string MainXaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='Discord WARP' Width='600' Height='720' WindowStartupLocation='CenterScreen' ResizeMode='CanMinimize'
        FlowDirection='RightToLeft' Background='#1E1F22' FontFamily='Segoe UI' FontSize='14' Foreground='#DBDEE1'>
  <Window.Resources>
    <Style TargetType='Button'>
      <Setter Property='Foreground' Value='#F2F3F5'/><Setter Property='Background' Value='#2B2D31'/>
      <Setter Property='BorderBrush' Value='#3F4147'/><Setter Property='Height' Value='46'/><Setter Property='Margin' Value='5'/>
      <Setter Property='Cursor' Value='Hand'/><Setter Property='FontSize' Value='14'/>
      <Setter Property='Template'><Setter.Value>
        <ControlTemplate TargetType='Button'>
          <Border x:Name='b' Background='{TemplateBinding Background}' BorderBrush='{TemplateBinding BorderBrush}' BorderThickness='1' CornerRadius='8'>
            <ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/></Border>
          <ControlTemplate.Triggers>
            <Trigger Property='IsMouseOver' Value='True'><Setter TargetName='b' Property='BorderBrush' Value='#5865F2'/></Trigger>
            <Trigger Property='IsEnabled' Value='False'><Setter TargetName='b' Property='Opacity' Value='0.4'/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate></Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <Grid Margin='20'>
    <Grid.RowDefinitions><RowDefinition Height='Auto'/><RowDefinition Height='Auto'/><RowDefinition Height='Auto'/><RowDefinition Height='*'/><RowDefinition Height='Auto'/></Grid.RowDefinitions>
    <DockPanel Grid.Row='0' Margin='2,0,2,14'>
      <TextBlock x:Name='Ver' DockPanel.Dock='Right' Foreground='#80848E' VerticalAlignment='Bottom' FontSize='12'/>
      <TextBlock Text='Discord WARP' FontSize='24' FontWeight='SemiBold' Foreground='#F2F3F5'/>
    </DockPanel>
    <Border Grid.Row='1' Background='#2B2D31' CornerRadius='12' Padding='18' Margin='0,0,0,12'>
      <StackPanel Orientation='Horizontal'>
        <Ellipse x:Name='Dot' Width='26' Height='26' Fill='#80848E' Margin='0,0,16,0' VerticalAlignment='Center'/>
        <StackPanel VerticalAlignment='Center'>
          <TextBlock x:Name='StatusTitle' Text='جارٍ الفحص...' FontSize='19' FontWeight='SemiBold' Foreground='#F2F3F5'/>
          <TextBlock x:Name='StatusSub' Foreground='#B5BAC1' Margin='0,4,0,0' TextWrapping='Wrap' MaxWidth='460'/>
        </StackPanel>
      </StackPanel>
    </Border>
    <Grid Grid.Row='2' Margin='0,0,0,12'>
      <Button x:Name='BtnInstall' Content='تثبيت' Height='56' FontSize='17' FontWeight='SemiBold' Background='#5865F2' BorderBrush='#5865F2' Visibility='Collapsed'/>
      <StackPanel x:Name='Actions'>
        <TextBlock Text='الديسكورد' Foreground='#80848E' FontSize='12' Margin='7,0,0,0'/>
        <Button x:Name='BtnDiscord' Content='فتح الديسكورد' Height='50' FontSize='15' FontWeight='SemiBold' Background='#5865F2' BorderBrush='#5865F2'/>
        <TextBlock Text='الصيانة' Foreground='#80848E' FontSize='12' Margin='7,8,0,0'/>
        <UniformGrid Rows='2' Columns='3'>
          <Button x:Name='BtnCheck' Content='فحص شامل'/>
          <Button x:Name='BtnRepair' Content='إصلاح'/>
          <Button x:Name='BtnPause' Content='إيقاف مؤقت'/>
          <Button x:Name='BtnUpdate' Content='البحث عن تحديث'/>
          <Button x:Name='BtnReport' Content='تقرير للمساعدة'/>
          <Button x:Name='BtnUninstall' Content='إزالة'/>
        </UniformGrid>
      </StackPanel>
    </Grid>
    <Border Grid.Row='3' Background='#2B2D31' CornerRadius='12' Padding='14'>
      <DockPanel>
        <TextBlock x:Name='ListTitle' DockPanel.Dock='Top' Text='التفاصيل' Foreground='#80848E' FontSize='12' Margin='0,0,0,8'/>
        <ScrollViewer VerticalScrollBarVisibility='Auto'><StackPanel x:Name='ListPanel'/></ScrollViewer>
      </DockPanel>
    </Border>
    <StackPanel Grid.Row='4' Margin='2,12,2,0'>
      <ProgressBar x:Name='Busy' Height='4' IsIndeterminate='True' Visibility='Hidden' Foreground='#5865F2' Background='#2B2D31' BorderThickness='0'/>
      <TextBlock x:Name='Foot' Foreground='#80848E' FontSize='12' Margin='0,6,0,0' TextWrapping='Wrap'/>
    </StackPanel>
  </Grid>
</Window>";

        static readonly Dictionary<string, string> Colors = new Dictionary<string, string> { { "green", "#23A55A" }, { "red", "#F23F43" }, { "orange", "#F0B232" }, { "grey", "#80848E" } };

        // English verify.ps1 line prefixes -> Arabic (first match wins)
        static readonly string[,] Tr = {
            { "DiscordWARP service running", "خدمة Discord WARP تعمل" }, { "DiscordWARP service not running", "خدمة Discord WARP متوقفة" },
            { "engine running", "محرك الاتصال يعمل" }, { "engine not running", "محرك الاتصال متوقف" },
            { "TUN adapter", "محوّل النفق" }, { "TUN routes present", "مسارات الديسكورد داخل النفق" }, { "TUN routes missing", "بعض مسارات الديسكورد مفقودة" },
            { "default route via", "باقي البرامج تستخدم الإنترنت العادي" }, { "default route goes through the TUN", "كل الإنترنت يمر بالنفق (خطأ)" },
            { "NRPT Discord rule present", "أسماء الديسكورد توجَّه إلى النفق" }, { "NRPT Discord rule missing", "توجيه أسماء الديسكورد مفقود" },
            { "TUN does not take over system DNS", "إعدادات DNS للكمبيوتر لم تتغير" },
            { "discord.com ->", "اسم discord.com يمر عبر النفق" }, { "www.google.com ->", "المواقع الأخرى تعمل بشكل عادي" },
            { "other apps:", "باقي البرامج على إنترنتك الأصلي" },
            { "WARP tunnel reachable", "نفق WARP متصل" }, { "WARP tunnel test failed", "نفق WARP لا يستجيب" },
            { "Discord API via WARP failed", "خوادم الديسكورد لا تستجيب عبر WARP" }, { "Discord API via WARP slow", "خوادم الديسكورد بطيئة عبر WARP" }, { "Discord API via WARP", "خوادم الديسكورد تستجيب عبر WARP" },
            { "DISCORD group = WARP only", "لا تسريب: الديسكورد عبر WARP فقط" },
            { "Discord app not running", "تطبيق الديسكورد مغلق حالياً" }, { "Discord running but idle", "تطبيق الديسكورد مفتوح بدون اتصالات الآن" },
            { "Discord connections NOT via WARP", "بعض اتصالات الديسكورد لا تمر عبر WARP" }, { "Discord app:", "تطبيق الديسكورد: كل اتصالاته عبر WARP" },
            { "no non-Discord process uses WARP", "لا يوجد برنامج آخر يستخدم WARP" }, { "non-Discord processes using WARP", "برامج أخرى تستخدم WARP" },
            { "last call", "آخر مكالمة صوتية مرّت عبر WARP" }, { "last media server", "خادم آخر مكالمة داخل النفق" },
            { "no voice call found", "لا توجد مكالمة سابقة للفحص" }, { "mihomo API not reachable", "تعذّر الاتصال بمحرك الاتصال" },
            { "no other engine", "لا يوجد برنامج آخر يتعارض مع النفق" }, { "another engine running", "يوجد برنامج آخر يتعارض مع النفق" } };

        static readonly string[,] Steps = {
            { "فحص الجهاز وملفات الحزمة", "package files: SHA-256 OK" }, { "نسخ البرنامج ومحرك الاتصال", "program files installed" },
            { "إنشاء حساب WARP مجاني لهذا الكمبيوتر", "WARP profile parsed" }, { "ضبط الإعدادات وفحصها", "engine config written" },
            { "تشغيل خدمة Discord WARP", "service: Running" }, { "توجيه أسماء الديسكورد", "NRPT: " },
            { "الاختصارات والتشغيل التلقائي", "shortcuts: " }, { "الفحص النهائي", "verify #" } };

        readonly string exeDir, scriptsDir, version;
        readonly bool isPackage, startHidden, autoInstall;
        Window win; Dictionary<string, FrameworkElement> ui = new Dictionary<string, FrameworkElement>();
        Forms.NotifyIcon notify; Forms.ToolStripMenuItem miPause, miUpdate;
        Dictionary<string, Drawing.Icon> icons = new Dictionary<string, Drawing.Icon>();
        string lastState = ""; bool quit, hintShown, busy;
        Dictionary<string, object> updateInfo;
        static string AppLog { get { return System.IO.Path.Combine(Paths.UserDir, "app.log"); } }

        public MainApp(bool hidden, bool auto)
        {
            exeDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
            isPackage = File.Exists(System.IO.Path.Combine(exeDir, @"setup\Install.ps1")) && !string.Equals(exeDir, Paths.InstallDir, StringComparison.OrdinalIgnoreCase);
            scriptsDir = isPackage ? System.IO.Path.Combine(exeDir, "setup") : System.IO.Path.Combine(Paths.InstallDir, "scripts");
            try { version = File.ReadAllText(System.IO.Path.Combine(isPackage ? scriptsDir : Paths.DataDir, isPackage ? "version.txt" : "version.txt")).Trim(); } catch { version = "?"; }
            startHidden = hidden && !isPackage; autoInstall = auto && isPackage;
        }

        public static void L(string m) { Log.Write(AppLog, m); }

        // ------------------------------------------------------------------ setup
        public void Run(EventWaitHandle showEvent)
        {
            var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            app.DispatcherUnhandledException += (s, e) => { L("UI error: " + e.Exception); e.Handled = true; SetBusy(false, "حدث خطأ: " + e.Exception.Message); };
            win = (Window)XamlReader.Parse(MainXaml);
            foreach (var n in new[] { "Ver", "Dot", "StatusTitle", "StatusSub", "BtnInstall", "Actions", "BtnDiscord", "BtnCheck", "BtnRepair", "BtnPause", "BtnUpdate", "BtnReport", "BtnUninstall", "ListTitle", "ListPanel", "Busy", "Foot" })
                ui[n] = (FrameworkElement)win.FindName(n);
            Txt("Ver").Text = "الإصدار " + version;
            foreach (var kv in Colors) { icons[kv.Key] = DotIcon(kv.Value, false); icons[kv.Key + "+u"] = DotIcon(kv.Value, true); }
            win.Icon = System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(AppIcon().Handle, Int32Rect.Empty, System.Windows.Media.Imaging.BitmapSizeOptions.FromEmptyOptions());

            notify = new Forms.NotifyIcon { Icon = icons["grey"], Text = "Discord WARP", Visible = !isPackage };
            var menu = new Forms.ContextMenuStrip { RightToLeft = Forms.RightToLeft.Yes };
            menu.Items.Add("فتح", null, (s, e) => ShowMain());
            menu.Items.Add("إصلاح", null, (s, e) => { ShowMain(); Repair(); });
            miPause = (Forms.ToolStripMenuItem)menu.Items.Add("إيقاف مؤقت", null, (s, e) => { ShowMain(); PauseResume(); });
            miUpdate = (Forms.ToolStripMenuItem)menu.Items.Add("البحث عن تحديثات", null, (s, e) => { ShowMain(); CheckUpdate(true); });
            menu.Items.Add(new Forms.ToolStripSeparator());
            menu.Items.Add("خروج", null, (s, e) => Exit());
            notify.ContextMenuStrip = menu;
            notify.DoubleClick += (s, e) => ShowMain(); notify.BalloonTipClicked += (s, e) => ShowMain();

            win.Closing += (s, e) =>
            {
                if (quit || isPackage) return;
                e.Cancel = true; win.Hide();
                if (!hintShown) { hintShown = true; notify.ShowBalloonTip(3000, "Discord WARP", "التطبيق ما زال يعمل هنا بجانب الساعة.", Forms.ToolTipIcon.Info); }
            };
            win.Closed += (s, e) => { notify.Visible = false; Application.Current.Shutdown(); };

            Btn("BtnDiscord").Click += (s, e) => DiscordButton();
            Btn("BtnCheck").Click += (s, e) => FullCheck();
            Btn("BtnRepair").Click += (s, e) => Repair();
            Btn("BtnPause").Click += (s, e) => PauseResume();
            Btn("BtnUpdate").Click += (s, e) => CheckUpdate(true);
            Btn("BtnReport").Click += (s, e) => Report();
            Btn("BtnUninstall").Click += (s, e) => Uninstall();
            Btn("BtnInstall").Click += (s, e) => Install(false);

            var pump = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
            pump.Tick += (s, e) => { if (showEvent.WaitOne(0)) ShowMain(); };
            pump.Start();
            var refresh = new DispatcherTimer { Interval = TimeSpan.FromMinutes(3) };
            refresh.Tick += (s, e) => UpdateStatus(); refresh.Start();
            if (!isPackage)
            {
                var upd = new DispatcherTimer { Interval = TimeSpan.FromSeconds(60) };
                upd.Tick += (s, e) => { upd.Interval = TimeSpan.FromHours(6); CheckUpdate(false); }; upd.Start();
            }

            var firstRun = System.IO.Path.Combine(Paths.UserDir, "first-run.flag");
            bool welcome = !isPackage && File.Exists(firstRun);
            if (welcome)
            {
                try { File.Delete(firstRun); } catch { }
                ClearList("مرحباً! تم التثبيت");
                AddRow("PASS", "الإعداد جاهز ويعمل تلقائياً مع Windows، وهذه الأيقونة تبقى بجانب الساعة.");
                AddRow("INFO", File.Exists(Paths.DiscordUpdateExe) ? "الديسكورد مثبّت عندك: اضغط \"فتح الديسكورد\"." : "ليس عندك ديسكورد؟ اضغط \"تحميل وتثبيت الديسكورد\" (الزر البنفسجي).");
            }
            UpdateDiscordButton();
            if (startHidden && !welcome) UpdateStatus(); else ShowMain();
            if (autoInstall) win.Dispatcher.BeginInvoke(new Action(() => Install(true)), DispatcherPriority.ApplicationIdle);
            app.Run();
            notify.Visible = false; notify.Dispose();
        }

        TextBlock Txt(string n) { return (TextBlock)ui[n]; }
        Button Btn(string n) { return (Button)ui[n]; }

        void ShowMain() { win.Show(); if (win.WindowState == WindowState.Minimized) win.WindowState = WindowState.Normal; win.Activate(); UpdateStatus(); }
        void Exit() { quit = true; notify.Visible = false; win.Close(); Application.Current.Shutdown(); }

        string Ask(string text, DlgKind k, params string[] buttons) { return Dlg.Show(win, text, k, buttons); }
        void Say(string text, DlgKind k) { Dlg.Ok(win, text, k); }

        void SetBusy(bool on, string msg)
        {
            busy = on;
            ui["Busy"].Visibility = on ? Visibility.Visible : Visibility.Hidden; Txt("Foot").Text = msg ?? "";
            foreach (var b in new[] { "BtnDiscord", "BtnCheck", "BtnRepair", "BtnPause", "BtnUpdate", "BtnReport", "BtnUninstall", "BtnInstall" }) ui[b].IsEnabled = !on;
        }
        void ClearList(string title) { ((StackPanel)ui["ListPanel"]).Children.Clear(); Txt("ListTitle").Text = title; }
        void AddRow(string state, string text)
        {
            string sym = "•", col = Colors["grey"];
            switch (state) { case "PASS": sym = "✓"; col = Colors["green"]; break; case "FAIL": sym = "✗"; col = Colors["red"]; break; case "WARN": sym = "!"; col = Colors["orange"]; break; case "RUN": sym = "…"; col = "#5865F2"; break; case "TODO": sym = "○"; col = "#4E5058"; break; }
            var sp = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 3, 0, 3) };
            sp.Children.Add(new TextBlock { Text = sym, Width = 22, FontWeight = FontWeights.Bold, Foreground = Dlg.B(col) });
            sp.Children.Add(new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, MaxWidth = 490 });
            ((StackPanel)ui["ListPanel"]).Children.Add(sp);
        }

        // ------------------------------------------------------------------ icons
        static Drawing.Icon DotIcon(string hex, bool badge)
        {
            var bmp = new Drawing.Bitmap(32, 32);
            using (var g = Drawing.Graphics.FromImage(bmp))
            {
                g.SmoothingMode = Drawing.Drawing2D.SmoothingMode.AntiAlias;
                g.FillEllipse(new Drawing.SolidBrush(Drawing.ColorTranslator.FromHtml("#2B2D31")), 0, 0, 31, 31);
                g.FillEllipse(new Drawing.SolidBrush(Drawing.ColorTranslator.FromHtml(hex)), 6, 6, 19, 19);
                if (badge) { g.FillEllipse(Drawing.Brushes.White, 17, -1, 16, 16); g.FillEllipse(new Drawing.SolidBrush(Drawing.ColorTranslator.FromHtml("#5865F2")), 19, 1, 12, 12); }
            }
            return Drawing.Icon.FromHandle(bmp.GetHicon());
        }
        static Drawing.Icon AppIcon()
        {
            try { return Drawing.Icon.ExtractAssociatedIcon(Process.GetCurrentProcess().MainModule.FileName); } catch { return DotIcon("#5865F2", false); }
        }

        // ------------------------------------------------------------------ status
        async void UpdateStatus()
        {
            var st = await Task.Run(() => Status.Read(true));
            ApplyStatus(st);
        }

        void ApplyStatus(Status r)
        {
            string state = "grey", title, sub = "";
            if (!r.Installed) { title = "غير مثبّت"; sub = isPackage ? "اضغط \"تثبيت\" للبدء. يستغرق دقيقة إلى 3 دقائق." : "شغّل ملف التثبيت."; }
            else if (r.Paused) { title = isPackage ? "مثبّت (متوقف مؤقتاً)" : "متوقف مؤقتاً"; sub = isPackage ? "التثبيت سيعيد التشغيل." : "الديسكورد لا يمر عبر WARP الآن. اضغط \"تشغيل\" للعودة."; }
            else if (!(r.ServiceRunning && r.EngineRunning && r.TunUp)) { state = "red"; title = "محرك الاتصال لا يعمل"; sub = "اضغط \"إصلاح\"."; }
            else if (!r.Nrpt) { state = "red"; title = "إعداد ناقص"; sub = "توجيه أسماء الديسكورد مفقود. اضغط \"إصلاح\" أو أعد التثبيت."; }
            else if (r.Delay < 0) { state = "red"; title = "نفق WARP لا يستجيب"; sub = "اضغط \"إصلاح\". إذا استمرت المشكلة اضغط \"تقرير للمساعدة\"."; }
            else if (r.Delay > 300) { state = "orange"; title = "الاتصال بطيء"; sub = "السرعة: " + r.Delay + " ms. جرّب \"إصلاح\" إذا كان الديسكورد بطيئاً."; }
            else { state = "green"; title = "الديسكورد يعمل عبر WARP"; sub = "السرعة: " + r.Delay + " ms  |  آخر فحص: " + DateTime.Now.ToString("HH:mm"); }
            ((Ellipse)ui["Dot"]).Fill = Dlg.B(Colors[state]); Txt("StatusTitle").Text = title; Txt("StatusSub").Text = sub;
            notify.Icon = icons[state + (updateInfo != null ? "+u" : "")];
            var tip = "Discord WARP: " + title; notify.Text = tip.Length > 63 ? tip.Substring(0, 63) : tip;
            ui["BtnInstall"].Visibility = isPackage ? Visibility.Visible : Visibility.Collapsed;
            ui["Actions"].Visibility = isPackage ? Visibility.Collapsed : Visibility.Visible;
            if (isPackage) Btn("BtnInstall").Content = r.Installed ? "تثبيت النسخة " + version + " (تحديث / إصلاح)" : "تثبيت";
            Btn("BtnPause").Content = r.Paused ? "تشغيل" : "إيقاف مؤقت"; miPause.Text = (string)Btn("BtnPause").Content;
            if (!busy) { Btn("BtnCheck").IsEnabled = r.Installed && !r.Paused; Btn("BtnRepair").IsEnabled = r.Installed && !r.Paused; }
            if ((lastState == "green" || lastState == "orange") && state == "red")
                notify.ShowBalloonTip(5000, "Discord WARP", title + " - افتح التطبيق واضغط \"إصلاح\".", Forms.ToolTipIcon.Warning);
            lastState = state;
            UpdateDiscordButton();
        }

        // ------------------------------------------------------------------ scripts (run only on demand)
        static string RunScript(string script, string args, int timeoutMs)
        {
            var psi = new ProcessStartInfo("powershell.exe", "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + script + "\" " + args)
            { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true, StandardOutputEncoding = Encoding.UTF8 };
            using (var p = Process.Start(psi))
            {
                var o = p.StandardOutput.ReadToEndAsync(); var e = p.StandardError.ReadToEndAsync();
                p.WaitForExit(timeoutMs); return o.Result + e.Result;
            }
        }
        static bool StartElevated(string script, string args)
        {
            try { Process.Start(new ProcessStartInfo("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\" " + args) { UseShellExecute = true, Verb = "runas", WindowStyle = ProcessWindowStyle.Hidden }); return true; }
            catch { return false; }   // UAC declined
        }
        static void StartHidden(string script, string args)
        {
            Process.Start(new ProcessStartInfo("powershell.exe", "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\" " + args) { UseShellExecute = false, CreateNoWindow = true });
        }

        // ------------------------------------------------------------------ buttons
        void UpdateDiscordButton() { Btn("BtnDiscord").Content = File.Exists(Paths.DiscordUpdateExe) ? "فتح الديسكورد" : "تحميل وتثبيت الديسكورد"; }

        async void DiscordButton()
        {
            if (File.Exists(Paths.DiscordUpdateExe)) { Process.Start(Paths.DiscordUpdateExe, "--processStart Discord.exe"); Txt("Foot").Text = "جارٍ فتح الديسكورد..."; return; }
            if (Ask("سيتم تحميل برنامج الديسكورد الرسمي (حوالي 160 ميغا) من موقع الديسكورد عبر WARP، ثم التأكد من توقيعه الرسمي وتثبيته.\nمتابعة؟", DlgKind.Question, "Yes", "نعم", "No", "لا") != "Yes") return;
            SetBusy(true, "جارٍ تحميل الديسكورد... (حسب سرعة الإنترنت، عادةً 1 إلى 5 دقائق)"); ClearList("تحميل الديسكورد"); AddRow("RUN", "تحميل المثبّت الرسمي من discord.com");
            string err = null, file = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "DiscordSetup.exe"); long size = 0;
            await Task.Run(() =>
            {
                try
                {
                    ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
                    using (var wc = new WebClient()) wc.DownloadFile("https://discord.com/api/downloads/distributions/app/installers/latest?channel=stable&platform=win&arch=x64", file);
                    size = new FileInfo(file).Length;
                    var sig = RunScript2("$s = Get-AuthenticodeSignature '" + file + "'; \"$($s.Status)|$($s.SignerCertificate.Subject)\"");
                    if (!sig.StartsWith("Valid|") || sig.IndexOf("Discord", StringComparison.OrdinalIgnoreCase) < 0) { File.Delete(file); err = "signature: " + sig; }
                }
                catch (Exception e) { err = e.Message; }
            });
            ClearList("تحميل الديسكورد");
            if (err != null) { AddRow("FAIL", "فشل التحميل أو التحقق من التوقيع"); SetBusy(false, "خطأ: " + err); Say("تعذّر تحميل الديسكورد.\nتأكد أن الحالة خضراء ثم حاول مرة ثانية.\n\n" + err, DlgKind.Warning); return; }
            AddRow("PASS", "تم التحميل (" + (size / 1048576) + " ميغا)"); AddRow("PASS", "التوقيع الرسمي من Discord سليم"); AddRow("RUN", "جارٍ التثبيت... سيفتح الديسكورد وحده عند الانتهاء");
            Process.Start(file); SetBusy(false, "بدأ تثبيت الديسكورد. سيفتح وحده خلال دقيقة.");
            var until = DateTime.Now.AddMinutes(10); var t = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
            t.Tick += (s, e) => { if (File.Exists(Paths.DiscordUpdateExe) || DateTime.Now > until) { t.Stop(); UpdateDiscordButton(); if (File.Exists(Paths.DiscordUpdateExe)) { ClearList("تحميل الديسكورد"); AddRow("PASS", "تم تثبيت الديسكورد. من الآن اضغط \"فتح الديسكورد\"."); } } };
            t.Start();
        }
        static string RunScript2(string command)
        {
            var psi = new ProcessStartInfo("powershell.exe", "-NoProfile -NonInteractive -Command \"" + command.Replace("\"", "\\\"") + "\"") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, StandardOutputEncoding = Encoding.UTF8 };
            using (var p = Process.Start(psi)) { var o = p.StandardOutput.ReadToEnd(); p.WaitForExit(60000); return o.Trim(); }
        }

        async void FullCheck()
        {
            SetBusy(true, "جارٍ الفحص الشامل... (حوالي 15 ثانية)"); ClearList("نتيجة الفحص الشامل");
            var outp = await Task.Run(() => RunScript(System.IO.Path.Combine(scriptsDir, "verify.ps1"), "", 120000));
            int pass = 0, fail = 0;
            foreach (var line in outp.Split('\n'))
            {
                var m = Regex.Match(line.Trim(), @"^\[(PASS|FAIL|WARN|INFO)\]\s+(.*)$"); if (!m.Success) continue;
                var st = m.Groups[1].Value; var txt = m.Groups[2].Value;
                if (st == "INFO" && txt.StartsWith("versions:")) continue;
                string ar = null; for (int i = 0; i < Tr.GetLength(0); i++) if (txt.StartsWith(Tr[i, 0])) { ar = Tr[i, 1]; break; }
                var ms = Regex.Match(txt, @"(\d+) ms"); if (ar != null && ms.Success) ar += " (" + ms.Groups[1].Value + " ms)";
                AddRow(st, ar ?? txt); if (st == "PASS") pass++; if (st == "FAIL") fail++;
            }
            SetBusy(false, fail > 0 ? fail + " فحص لم ينجح. جرّب \"إصلاح\"." : "كل الفحوصات سليمة (" + pass + ").");
            UpdateStatus();
        }

        async void Repair()
        {
            if (await Task.Run(() => Mihomo.DiscordInCall()) && Ask("أنت في مكالمة ديسكورد الآن. الإصلاح سيقطعها لثوانٍ. متابعة؟", DlgKind.Warning, "Yes", "نعم", "No", "لا") != "Yes") return;
            SetBusy(true, "جارٍ إعادة تشغيل الاتصال... (حوالي 15 ثانية)"); ClearList("إصلاح"); AddRow("RUN", "إعادة تشغيل محرك الاتصال وإنشاء نفق WARP جديد");
            string err = null;
            await Task.Run(() => { try { Ctl.Send(Status.NrptPresent() ? Ctl.RestartEngine : Ctl.Resume); Thread.Sleep(12000); } catch (Exception e) { err = e.Message; } });
            ClearList("إصلاح"); AddRow(err == null ? "PASS" : "FAIL", err == null ? "تمت إعادة التشغيل" : "تعذّر الإصلاح: " + err);
            SetBusy(false, err == null ? "انتهى الإصلاح. يتم تحديث الحالة..." : ""); UpdateStatus();
        }

        async void PauseResume()
        {
            bool paused = File.Exists(Paths.PausedFlag);
            var q = paused ? "تشغيل مرور الديسكورد عبر WARP مرة ثانية؟"
                           : "إيقاف مؤقت: الديسكورد سيتوقف عن المرور عبر WARP (سيعود محجوباً) حتى تضغط \"تشغيل\".\nمفيد إذا أردت استخدام VPN آخر. يبقى الإيقاف حتى بعد إعادة تشغيل الكمبيوتر.\nمتابعة؟";
            if (Ask(q, DlgKind.Question, "Yes", paused ? "تشغيل" : "إيقاف مؤقت", "No", "إلغاء") != "Yes") return;
            SetBusy(true, paused ? "جارٍ التشغيل..." : "جارٍ الإيقاف...");
            string err = null;
            await Task.Run(() => { try { Ctl.Send(paused ? Ctl.Resume : Ctl.Pause); Thread.Sleep(paused ? 12000 : 5000); } catch (Exception e) { err = e.Message; } });
            SetBusy(false, err == null ? "" : "خطأ: " + err); UpdateStatus();
        }

        async void Report()
        {
            SetBusy(true, "جارٍ تجهيز التقرير... (حوالي 20 ثانية)");
            var outp = await Task.Run(() => RunScript(System.IO.Path.Combine(scriptsDir, "Report.ps1"), "", 180000));
            var zip = outp.Split('\n').Select(x => x.Trim()).LastOrDefault(x => x.EndsWith(".zip"));
            SetBusy(false, zip != null ? "تم حفظ التقرير على سطح المكتب: " + zip : "تعذّر إنشاء التقرير.");
            if (zip == null) return;
            Say("تم حفظ التقرير على سطح المكتب:\n" + zip + "\n\nأرسل هذا الملف لمن يساعدك. لا يحتوي على كلمات سر أو مفاتيح.", DlgKind.Success);
            Process.Start("explorer.exe", "/select,\"" + zip + "\"");
        }

        void Uninstall()
        {
            var a = Ask("إزالة Discord WARP من هذا الكمبيوتر:\n\nحذف كل شيء: البرنامج والخدمة وحساب WARP والسجلات.\nالإعدادات فقط: يبقى حساب WARP (لإعادة التثبيت لاحقاً).\n\nبعد الإزالة يعود ديسكورد محجوباً كما كان.",
                        DlgKind.Warning, "Full", "حذف كل شيء", "Settings", "الإعدادات فقط", "Cancel", "إلغاء");
            if (a == "Cancel") return;
            // the uninstaller copies itself to TEMP, asks for admin and removes the program folder (including this exe)
            StartHidden(System.IO.Path.Combine(scriptsDir, "Uninstall.ps1"), "-Mode " + a);
            Exit();
        }

        // ------------------------------------------------------------------ updates
        static string InstalledVersion() { try { return File.ReadAllText(Paths.VersionFile).Trim(); } catch { return "0.0.0"; } }
        string SnoozeFile { get { return System.IO.Path.Combine(Paths.UserDir, "update-snooze.txt"); } }

        async void CheckUpdate(bool interactive)
        {
            if (isPackage) return;
            if (interactive) { SetBusy(true, "جارٍ البحث عن تحديثات..."); ClearList("التحديثات"); AddRow("RUN", "جارٍ البحث عن نسخة أحدث على GitHub..."); }
            Dictionary<string, object> rel = null; string err = null;
            await Task.Run(() =>
            {
                try
                {
                    ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
                    using (var wc = new WebClient())
                    {
                        wc.Headers.Add("User-Agent", "discord-warp-app"); wc.Encoding = Encoding.UTF8;
                        var tok = Environment.GetEnvironmentVariable("DWARP_GH_TOKEN"); if (!string.IsNullOrEmpty(tok)) wc.Headers.Add("Authorization", "Bearer " + tok);
                        rel = Json.Parse(wc.DownloadString("https://api.github.com/repos/" + Paths.Repo + "/releases/latest"));
                    }
                }
                catch (Exception e) { err = e.Message; }
            });
            if (interactive) { SetBusy(false, ""); ClearList("التحديثات"); }
            if (rel == null) { if (interactive) { AddRow("FAIL", "تعذّر الوصول إلى صفحة التحديثات"); Say("تعذّر فحص التحديثات الآن.\nتأكد من الإنترنت ثم حاول مرة ثانية.", DlgKind.Warning); } return; }
            var tag = Convert.ToString(Json.Get(rel, "tag_name")).TrimStart('v'); var cur = InstalledVersion();
            Version vt, vc; if (!Version.TryParse(tag, out vt) || !Version.TryParse(cur, out vc)) vc = vt = new Version(0, 0);
            if (vt <= vc)
            {
                updateInfo = null; SetUpdateBadge();
                if (interactive) { AddRow("PASS", "لديك آخر نسخة (" + cur + ")"); Say("لديك آخر نسخة (" + cur + ").\nلا يوجد تحديث.", DlgKind.Success); }
                return;
            }
            updateInfo = rel; SetUpdateBadge();
            if (interactive) AddRow("INFO", "يوجد تحديث: " + tag + " (نسختك: " + cur + ")");
            else
            {
                try { var s = File.ReadAllText(SnoozeFile).Trim().Split('|'); if (s.Length == 2 && s[0] == tag && DateTime.Parse(s[1]) > DateTime.Now) return; } catch { }
            }
            var body = Convert.ToString(Json.Get(rel, "body"));
            var notes = string.Join("\n", body.Split('\n').Select(x => x.Trim()).Where(x => Regex.IsMatch(x, @"[؀-ۿ]")));
            if (notes.Length > 400) notes = notes.Substring(0, 400) + " ...";
            if (!startHidden || interactive) ShowMain();
            var a = Dlg.Show(win.IsVisible ? win : null, "يوجد تحديث جديد لأداة Discord WARP.\n\nالنسخة الجديدة: " + tag + "\nنسختك الحالية: " + cur + "\n\n" + notes + "\n\nتحميل وتثبيت التحديث الآن؟ سيطلب Windows صلاحية المسؤول.",
                             DlgKind.Question, "Yes", "تحديث الآن", "No", "لاحقاً");
            if (a != "Yes") { if (!interactive) { try { Directory.CreateDirectory(Paths.UserDir); File.WriteAllText(SnoozeFile, tag + "|" + DateTime.Now.AddDays(1).ToString("o")); } catch { } } return; }
            StartHidden(System.IO.Path.Combine(scriptsDir, "Update.ps1"), "-Yes");
            Exit();
        }
        void SetUpdateBadge()
        {
            bool has = updateInfo != null; var tag = has ? Convert.ToString(Json.Get(updateInfo, "tag_name")).TrimStart('v') : "";
            Btn("BtnUpdate").Content = has ? "تحديث متاح (" + tag + ")" : "البحث عن تحديث";
            Btn("BtnUpdate").Background = Dlg.B(has ? "#5865F2" : "#2B2D31");
            miUpdate.Text = has ? "تحديث متاح: " + tag : "البحث عن تحديثات";
            if (lastState != "") notify.Icon = icons[lastState + (has ? "+u" : "")];
        }

        // ------------------------------------------------------------------ install (package mode)
        void Install(bool skipConfirm)
        {
            var q = "سيتم إعداد ديسكورد ليعمل عبر Cloudflare WARP على هذا الكمبيوتر (باقي البرامج لا تتأثر):\n- تثبيت برنامج Discord WARP ومحرك الاتصال\n- إنشاء حساب WARP مجاني لهذا الكمبيوتر\n- ضبط التشغيل التلقائي\n- إذا كان برنامج Cloudflare WARP الرسمي متصلاً سيتم فصله\n\nأطفئ أي VPN آخر قبل البدء. سيطلب Windows صلاحية المسؤول. متابعة؟";
            if (!skipConfirm && Ask(q, DlgKind.Question, "Yes", "تثبيت", "No", "إلغاء") != "Yes") return;
            var log = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "discord-warp-install-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".log");
            if (!StartElevated(System.IO.Path.Combine(scriptsDir, "Install.ps1"), "-NoPopups -ProgressLog \"" + log + "\"")) { Txt("Foot").Text = "تم إلغاء التثبيت (لم تتم الموافقة على صلاحية المسؤول)."; return; }
            SetBusy(true, "جارٍ التثبيت... لا تغلق النافذة"); Txt("StatusTitle").Text = "جارٍ التثبيت..."; Txt("StatusSub").Text = "";
            var start = DateTime.Now; var t = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            t.Tick += (s, e) =>
            {
                string all = ""; try { all = File.ReadAllText(log, Encoding.UTF8); } catch { }
                ClearList("خطوات التثبيت");
                int reached = -1; for (int i = 0; i < Steps.GetLength(0); i++) if (all.Contains(Steps[i, 1])) reached = i;
                string end = all.Contains("=== SETUP OK ===") ? "ok" : all.Contains("SETUP FINISHED WITH FAILED CHECKS") ? "partial" : Regex.IsMatch(all, "FAILED: |cancelled by user") ? "fail" : "";
                if (end == "" && (DateTime.Now - start).TotalMinutes > 12) end = "fail";
                for (int i = 0; i < Steps.GetLength(0); i++)
                {
                    string st = (i <= reached && (end == "ok" || i < reached)) ? "PASS" : (i == reached || (i == reached + 1 && end == "")) ? (end == "fail" ? "FAIL" : "RUN") : "TODO";
                    AddRow(st, Steps[i, 0]);
                }
                if (end == "") return;
                t.Stop(); SetBusy(false, "");
                if (end == "ok")
                {
                    ((Ellipse)ui["Dot"]).Fill = Dlg.B(Colors["green"]); Txt("StatusTitle").Text = "تم التثبيت بنجاح"; Txt("StatusSub").Text = "";
                    Say("تم التثبيت بنجاح ✔\n\nسيفتح الآن تطبيق Discord WARP من مكانه الدائم، وتجده لاحقاً في قائمة ابدأ وعلى سطح المكتب.\nيمكنك حذف مجلد التثبيت هذا.", DlgKind.Success);
                    quit = true; win.Close();
                    try { Process.Start(System.IO.Path.Combine(Paths.InstallDir, "DiscordWARP.exe")); } catch { }
                    Application.Current.Shutdown();
                }
                else
                {
                    var why = all.Split('\n').Where(x => x.Contains("FAILED: ")).Select(x => x.Substring(x.IndexOf("FAILED: ") + 8).Trim()).LastOrDefault() ?? "";
                    ((Ellipse)ui["Dot"]).Fill = Dlg.B(Colors["red"]); Txt("StatusTitle").Text = end == "partial" ? "انتهى التثبيت مع مشكلة" : "لم يكتمل التثبيت"; Txt("StatusSub").Text = "السجل: " + log;
                    Say(Txt("StatusTitle").Text + ".\n" + why + "\n\nأعد تشغيل الكمبيوتر وحاول مرة ثانية، أو أرسل ملف السجل:\n" + log, DlgKind.Warning);
                }
            };
            t.Start();
        }
    }
}
