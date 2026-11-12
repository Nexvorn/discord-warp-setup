# Styled dialog for DiscordWARP-Setup (WPF, dark theme, RTL, rounded) - replaces the plain Windows message boxes.
# Usage:  . "$PSScriptRoot\Dialog.ps1";  Show-DwDialog -Text '...' -Kind question -Buttons YesNo   -> 'Yes' | 'No' | 'OK' | 'Cancel'
# -Labels overrides the button captions (same order as the button set).  Esc = No/Cancel, Enter = first button.
# NOTE: contains Arabic text - saved as UTF-8 WITH BOM by build.ps1. Needs an STA thread (Windows PowerShell 5.1 default).
function Show-DwDialog {
  param([string]$Text, [string]$Title = 'Discord WARP', [ValidateSet('OK', 'YesNo', 'YesNoCancel')][string]$Buttons = 'OK',
        [ValidateSet('info', 'question', 'warning', 'error', 'success')][string]$Kind = 'info', $Owner = $null, [string[]]$Labels = $null)
  Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
  $accent = @{ info = '#5865F2'; question = '#5865F2'; warning = '#F0B232'; error = '#F23F43'; success = '#23A55A' }[$Kind]
  $glyph  = @{ info = 'i'; question = '?'; warning = '!'; error = '×'; success = '✓' }[$Kind]
  $sets = @{ OK = ,@('OK', 'موافق');   # leading comma: keep a one-button set as an array of pairs (PowerShell unrolls @(@(..)))
            YesNo = @(@('Yes', 'نعم'), @('No', 'لا')); YesNoCancel = @(@('Yes', 'نعم'), @('No', 'لا'), @('Cancel', 'إلغاء')) }
  $btns = $sets[$Buttons]
  if ($Labels) { for ($i = 0; $i -lt [Math]::Min($Labels.Count, $btns.Count); $i++) { $btns[$i] = @($btns[$i][0], $Labels[$i]) } }
  [xml]$x = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" SizeToContent="WidthAndHeight" ResizeMode="NoResize"
        WindowStartupLocation="CenterScreen" Topmost="True" FlowDirection="RightToLeft" FontFamily="Segoe UI" FontSize="14" Title="Discord WARP">
  <Border Background="#2B2D31" BorderBrush="#3F4147" BorderThickness="1" CornerRadius="14" Padding="22,18,22,18" Margin="12" MinWidth="400" MaxWidth="540">
    <Border.Effect><DropShadowEffect BlurRadius="18" ShadowDepth="0" Opacity="0.55"/></Border.Effect>
    <StackPanel>
      <TextBlock x:Name="T" Foreground="#80848E" FontSize="12" Margin="0,0,0,12"/>
      <DockPanel>
        <Grid DockPanel.Dock="Left" Width="40" Height="40" Margin="0,0,16,0" VerticalAlignment="Top">
          <Ellipse x:Name="C"/>
          <TextBlock x:Name="G" Foreground="White" FontWeight="Bold" FontSize="20" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Grid>
        <TextBlock x:Name="M" Foreground="#F2F3F5" FontSize="15" TextWrapping="Wrap" LineHeight="23" VerticalAlignment="Center"/>
      </DockPanel>
      <StackPanel x:Name="B" Orientation="Horizontal" HorizontalAlignment="Left" Margin="0,20,0,0"/>
    </StackPanel>
  </Border>
</Window>
'@
  $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
  $br = { param($h) New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($h)) }
  $w.FindName('T').Text = $Title; $w.FindName('M').Text = $Text
  $w.FindName('C').Fill = & $br $accent; $w.FindName('G').Text = $glyph
  $panel = $w.FindName('B'); $first = $true
  foreach ($b in $btns) {
    $btn = New-Object Windows.Controls.Button
    $btn.Content = $b[1]; $btn.Tag = $b[0]; $btn.MinWidth = 96; $btn.Height = 38; $btn.Margin = '0,0,10,0'; $btn.Cursor = 'Hand'
    $btn.Foreground = & $br '#FFFFFF'; $btn.FontSize = 14; $btn.Padding = '16,0,16,0'
    $btn.Background = & $br $(if ($first) { '#5865F2' } else { '#3F4147' }); $btn.BorderThickness = 0
    $tpl = '<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button"><Border Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border></ControlTemplate>'
    $btn.Template = [Windows.Markup.XamlReader]::Parse($tpl)
    $btn.IsDefault = $first; $btn.IsCancel = ($b[0] -in 'No', 'Cancel' -and $b -eq $btns[-1]) -or ($btns.Count -eq 1)
    $btn.Add_Click({ $win = [Windows.Window]::GetWindow($this); $win.Tag = $this.Tag; $win.Close() })
    [void]$panel.Children.Add($btn); $first = $false
  }
  $w.Add_MouseLeftButtonDown({ try { $this.DragMove() } catch {} })
  if ($Owner -and $Owner.IsVisible) { $w.Owner = $Owner; $w.WindowStartupLocation = 'CenterOwner'; $w.ShowInTaskbar = $false }
  [void]$w.ShowDialog()
  if ($w.Tag) { [string]$w.Tag } elseif ($Buttons -eq 'OK') { 'OK' } elseif ($Buttons -eq 'YesNo') { 'No' } else { 'Cancel' }
}
