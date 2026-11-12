// Discord WARP v2 - styled dialog (dark, rounded, right-to-left), replaces Windows message boxes.
using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Shapes;

namespace DiscordWarp
{
    public enum DlgKind { Info, Question, Warning, Error, Success }

    public static class Dlg
    {
        const string Xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        WindowStyle='None' AllowsTransparency='True' Background='Transparent' SizeToContent='WidthAndHeight' ResizeMode='NoResize'
        WindowStartupLocation='CenterScreen' Topmost='True' FlowDirection='RightToLeft' FontFamily='Segoe UI' FontSize='14' Title='Discord WARP' ShowInTaskbar='True'>
  <Border Background='#2B2D31' BorderBrush='#3F4147' BorderThickness='1' CornerRadius='14' Padding='22,18,22,18' Margin='12' MinWidth='400' MaxWidth='540'>
    <Border.Effect><DropShadowEffect BlurRadius='18' ShadowDepth='0' Opacity='0.55'/></Border.Effect>
    <StackPanel>
      <TextBlock x:Name='T' Text='Discord WARP' Foreground='#80848E' FontSize='12' Margin='0,0,0,12'/>
      <DockPanel>
        <Grid DockPanel.Dock='Left' Width='40' Height='40' Margin='0,0,16,0' VerticalAlignment='Top'>
          <Ellipse x:Name='C'/>
          <TextBlock x:Name='G' Foreground='White' FontWeight='Bold' FontSize='20' HorizontalAlignment='Center' VerticalAlignment='Center'/>
        </Grid>
        <TextBlock x:Name='M' Foreground='#F2F3F5' FontSize='15' TextWrapping='Wrap' LineHeight='23' VerticalAlignment='Center'/>
      </DockPanel>
      <StackPanel x:Name='B' Orientation='Horizontal' HorizontalAlignment='Left' Margin='0,20,0,0'/>
    </StackPanel>
  </Border>
</Window>";
        const string BtnTpl = "<ControlTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' TargetType='Button'><Border Background='{TemplateBinding Background}' CornerRadius='8' Padding='{TemplateBinding Padding}'><ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/></Border></ControlTemplate>";

        public static Brush B(string hex) { return new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex)); }

        /// <summary>buttons: pairs of (result, label); first = default (purple). Returns the result string of the clicked button.</summary>
        public static string Show(Window owner, string text, DlgKind kind, params string[] buttons)
        {
            if (buttons == null || buttons.Length == 0) buttons = new[] { "OK", "موافق" };
            var w = (Window)XamlReader.Parse(Xaml);
            string accent = "#5865F2", glyph = "i";
            switch (kind)
            {
                case DlgKind.Question: glyph = "?"; break;
                case DlgKind.Warning: accent = "#F0B232"; glyph = "!"; break;
                case DlgKind.Error: accent = "#F23F43"; glyph = "×"; break;
                case DlgKind.Success: accent = "#23A55A"; glyph = "✓"; break;
            }
            ((Ellipse)w.FindName("C")).Fill = B(accent);
            ((TextBlock)w.FindName("G")).Text = glyph;
            ((TextBlock)w.FindName("M")).Text = text;
            var panel = (StackPanel)w.FindName("B");
            string result = null, cancel = buttons[buttons.Length - 2];
            var tpl = (ControlTemplate)XamlReader.Parse(BtnTpl);
            for (int i = 0; i + 1 < buttons.Length; i += 2)
            {
                var res = buttons[i];
                var btn = new Button { Content = buttons[i + 1], MinWidth = 96, Height = 38, Margin = new Thickness(0, 0, 10, 0), Padding = new Thickness(16, 0, 16, 0),
                                       Foreground = Brushes.White, FontSize = 14, BorderThickness = new Thickness(0), Template = tpl,
                                       Background = B(i == 0 ? "#5865F2" : "#3F4147"), IsDefault = i == 0, Cursor = System.Windows.Input.Cursors.Hand };
                btn.Click += (s, e) => { result = res; w.Close(); };
                panel.Children.Add(btn);
            }
            w.KeyDown += (s, e) => { if (e.Key == System.Windows.Input.Key.Escape) { result = cancel; w.Close(); } };
            w.MouseLeftButtonDown += (s, e) => { try { w.DragMove(); } catch { } };
            if (owner != null && owner.IsVisible) { w.Owner = owner; w.WindowStartupLocation = WindowStartupLocation.CenterOwner; w.ShowInTaskbar = false; }
            w.ShowDialog();
            return result ?? cancel;
        }

        public static void Ok(Window owner, string text, DlgKind kind) { Show(owner, text, kind, "OK", "موافق"); }
        public static bool YesNo(Window owner, string text, DlgKind kind, string yes = "نعم", string no = "لا") { return Show(owner, text, kind, "Yes", yes, "No", no) == "Yes"; }
    }
}
