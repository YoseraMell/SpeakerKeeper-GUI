param([switch]$Minimized)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

$script:root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:engine = Join-Path $script:root 'SpeakerKeeper.ps1'
$script:settingsFile = Join-Path $script:root 'settings.txt'
$script:launcher = Join-Path $script:root 'Launch-GUI.vbs'
$script:dataDir = Join-Path $env:LOCALAPPDATA 'NZXT-Relay-Keeper'
$script:logFile = Join-Path $script:dataDir 'SpeakerKeeper.log'
$script:guiSettingsFile = Join-Path $script:dataDir 'gui.json'
$script:stopFile = Join-Path $script:dataDir ('stop-' + $PID + '.signal')
$script:startupItem = Join-Path ([Environment]::GetFolderPath('Startup')) 'NZXT Relay Keeper.lnk'
$script:legacyStartupItem = Join-Path ([Environment]::GetFolderPath('Startup')) 'SpeakerKeeper.lnk'
$script:worker = $null
$script:exiting = $false
$script:lastLogLength = -1

New-Item -ItemType Directory -Force -Path $script:dataDir | Out-Null
$created = $false
$script:mutex = New-Object System.Threading.Mutex($true, 'Local\SpeakerKeeper_GUI_SingleInstance', [ref]$created)
if (-not $created) { exit }

function Read-KeeperSettings {
    $s = @{
        Frequency = '500'
        Amplitude = '0.075'
        LingerSeconds = '60'
        Threshold = '0.001'
        DeviceName = ''
        AppName = ''
    }
    if (Test-Path -LiteralPath $script:settingsFile) {
        foreach ($line in [System.IO.File]::ReadAllLines($script:settingsFile)) {
            if ($line -match '^\s*([A-Za-z]+)\s*=(.*)$' -and $s.ContainsKey($Matches[1])) {
                $s[$Matches[1]] = $Matches[2].Trim()
            }
        }
    }
    return $s
}

function Write-KeeperSettings([hashtable]$updates) {
    $lines = if (Test-Path -LiteralPath $script:settingsFile) {
        [System.IO.File]::ReadAllLines($script:settingsFile)
    } else {
        @('# SpeakerKeeper GUI settings', 'SoundKeeper=SoundKeeper64.exe')
    }
    $out = New-Object 'System.Collections.Generic.List[string]'
    $seen = @{}
    foreach ($line in $lines) {
        if ($line -match '^\s*([A-Za-z]+)\s*=') {
            $key = $Matches[1]
            if ($updates.ContainsKey($key)) {
                $out.Add($key + '=' + $updates[$key])
                $seen[$key] = $true
                continue
            }
        }
        $out.Add($line)
    }
    foreach ($key in $updates.Keys) {
        if (-not $seen.ContainsKey($key)) { $out.Add($key + '=' + $updates[$key]) }
    }
    $tmp = $script:settingsFile + '.tmp'
    [System.IO.File]::WriteAllLines($tmp, $out, (New-Object System.Text.UTF8Encoding($true)))
    Move-Item -LiteralPath $tmp -Destination $script:settingsFile -Force
}

function Get-GuiTheme {
    if (Test-Path -LiteralPath $script:guiSettingsFile) {
        try {
            $p = Get-Content -LiteralPath $script:guiSettingsFile -Raw | ConvertFrom-Json
            if ($p.theme -eq 'Light') { return 'Light' }
        } catch { }
    }
    return 'Dark'
}

function Save-GuiTheme([string]$theme) {
    @{ theme = $theme } | ConvertTo-Json | Set-Content -LiteralPath $script:guiSettingsFile -Encoding UTF8
}

function Is-Monitoring {
    return ($null -ne $script:worker -and -not $script:worker.HasExited)
}

function Start-Monitoring {
    if (Is-Monitoring) { return }
    if (-not (Test-Path -LiteralPath $script:engine)) {
        [System.Windows.MessageBox]::Show('SpeakerKeeper.ps1 was not found.') | Out-Null
        return
    }
    Remove-Item -LiteralPath $script:stopFile -Force -ErrorAction SilentlyContinue
    $ps = Join-Path $PSHOME 'powershell.exe'
    $args = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -StopFile "{1}" -LogFile "{2}"' -f $script:engine, $script:stopFile, $script:logFile
    $script:worker = Start-Process -FilePath $ps -ArgumentList $args -WindowStyle Hidden -PassThru
    Update-Status
}

function Stop-Monitoring {
    if (-not (Is-Monitoring)) { return }
    [System.IO.File]::WriteAllText($script:stopFile, 'stop')
    if (-not $script:worker.WaitForExit(3000)) {
        # Only clean up the SoundKeeper children of our worker, never all soundkeepers on the PC.
        try {
            $children = @(Get-CimInstance Win32_Process -Filter ('ParentProcessId=' + $script:worker.Id) -ErrorAction SilentlyContinue)
            foreach ($child in $children) {
                if ($child.Name -like 'SoundKeeper*.exe') {
                    Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue
                }
            }
        } catch { }
        try { $script:worker.Kill() } catch { }
    }
    $script:worker.Dispose()
    $script:worker = $null
    Remove-Item -LiteralPath $script:stopFile -Force -ErrorAction SilentlyContinue
    Update-Status
}

function Set-Startup([bool]$enabled) {
    if ($enabled) {
        if (-not (Test-Path -LiteralPath $script:launcher)) { throw 'Launch-GUI.vbs is missing.' }
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($script:startupItem)
        $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
        $shortcut.Arguments = ('"{0}" --minimized' -f $script:launcher)
        $shortcut.WorkingDirectory = $script:root
        $shortcut.Description = 'NZXT Relay Keeper GUI (tray startup)'
        $shortcut.Save()
        Remove-Item -LiteralPath $script:legacyStartupItem -Force -ErrorAction SilentlyContinue
    } else {
        Remove-Item -LiteralPath $script:startupItem -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:legacyStartupItem -Force -ErrorAction SilentlyContinue
    }
}

function Refresh-AppList([string]$selectedName) {
    $script:appBox.Items.Clear()
    $script:appBox.Items.Add([pscustomobject]@{ Display = 'すべてのアプリ'; ProcessName = '' }) | Out-Null
    $names = @{}
    foreach ($p in Get-Process -ErrorAction SilentlyContinue) {
        try {
            if ($p.MainWindowHandle -ne [IntPtr]::Zero -and -not [string]::IsNullOrWhiteSpace($p.ProcessName)) {
                $names[$p.ProcessName] = $true
            }
        } catch { }
    }
    foreach ($name in @($names.Keys | Sort-Object)) {
        $script:appBox.Items.Add([pscustomobject]@{ Display = $name; ProcessName = $name }) | Out-Null
    }
    if ($selectedName -and -not $names.ContainsKey($selectedName)) {
        $script:appBox.Items.Add([pscustomobject]@{
            Display = ($selectedName + ' (起動していません)')
            ProcessName = $selectedName
        }) | Out-Null
    }
    $script:appBox.SelectedValue = $selectedName
    if ($script:appBox.SelectedIndex -lt 0) { $script:appBox.SelectedIndex = 0 }
}

function Update-Status {
    if ($null -eq $script:statusText) { return }
    if (Is-Monitoring) {
        $script:statusText.Text = '監視中'
        $script:toggleButton.Content = '監視を停止'
        $script:tray.Text = 'NZXT Relay Keeper - Monitoring'
    } else {
        $script:statusText.Text = '停止中'
        $script:toggleButton.Content = '監視を開始'
        $script:tray.Text = 'NZXT Relay Keeper - Stopped'
    }
}

function Update-Log {
    if (-not (Test-Path -LiteralPath $script:logFile)) { return }
    try {
        $size = (Get-Item -LiteralPath $script:logFile).Length
        if ($size -eq $script:lastLogLength) { return }
        $script:lastLogLength = $size
        $lines = @(Get-Content -LiteralPath $script:logFile -Tail 120 -Encoding UTF8)
        $script:consoleBox.Text = $lines -join [Environment]::NewLine
        $script:consoleBox.ScrollToEnd()
    } catch { }
}

function Apply-Theme([string]$theme) {
    if ($theme -eq 'Light') {
        $palette = @{
            WindowBrush = '#F2F5F9'; CardBrush = '#FFFFFF'; FieldBrush = '#E9EDF4'
            TextBrush = '#182334'; SubtleBrush = '#5D6B7D'; BorderBrush = '#D7DFE9'
        }
    } else {
        $palette = @{
            WindowBrush = '#101827'; CardBrush = '#1B2739'; FieldBrush = '#29384D'
            TextBrush = '#EDF3FA'; SubtleBrush = '#A7B5C5'; BorderBrush = '#3A4960'
        }
    }
    foreach ($name in $palette.Keys) {
        $color = [System.Windows.Media.ColorConverter]::ConvertFromString($palette[$name])
        $script:window.Resources[$name] = [System.Windows.Media.SolidColorBrush]::new($color)
    }
}

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NZXT Relay Keeper" Width="440" Height="670" MinWidth="410" MinHeight="550"
        WindowStartupLocation="CenterScreen" Background="{DynamicResource WindowBrush}">
  <Window.Resources>
    <SolidColorBrush x:Key="WindowBrush" Color="#101827"/>
    <SolidColorBrush x:Key="CardBrush" Color="#1B2739"/>
    <SolidColorBrush x:Key="FieldBrush" Color="#29384D"/>
    <SolidColorBrush x:Key="TextBrush" Color="#EDF3FA"/>
    <SolidColorBrush x:Key="SubtleBrush" Color="#A7B5C5"/>
    <SolidColorBrush x:Key="BorderBrush" Color="#3A4960"/>
    <SolidColorBrush x:Key="AccentBrush" Color="#417DDC"/>
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="{DynamicResource FieldBrush}"/>
      <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
      <Setter Property="Padding" Value="8,6"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Background" Value="{DynamicResource FieldBrush}"/>
      <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
      <Setter Property="Padding" Value="8,5"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
    </Style>
    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
      <Setter Property="Background" Value="{DynamicResource CardBrush}"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Background" Value="{DynamicResource AccentBrush}"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="12,8"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
    <Style TargetType="Expander">
      <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
    </Style>
  </Window.Resources>
  <Grid Margin="20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>
    <Grid Grid.Row="0" Margin="0,0,0,14">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="120"/>
      </Grid.ColumnDefinitions>
      <StackPanel>
        <TextBlock Text="NZXT Relay Keeper" FontSize="23" FontWeight="SemiBold"/>
        <TextBlock Text="Speaker Power Management" Foreground="{DynamicResource SubtleBrush}" FontSize="12"/>
      </StackPanel>
      <ComboBox x:Name="ThemeBox" Grid.Column="1" Margin="6,4,0,4">
        <ComboBoxItem Content="Dark"/>
        <ComboBoxItem Content="Light"/>
      </ComboBox>
    </Grid>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
      <StackPanel>
        <Border Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource BorderBrush}"
                BorderThickness="1" CornerRadius="12" Padding="14" Margin="0,0,0,12">
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <StackPanel>
              <TextBlock x:Name="StatusText" Text="停止中" FontSize="17" FontWeight="SemiBold"/>
              <TextBlock Text="検出対象アプリの音声を監視します" Foreground="{DynamicResource SubtleBrush}" FontSize="11"/>
            </StackPanel>
            <Button x:Name="ToggleButton" Grid.Column="1" Content="監視を開始" Margin="10,0,0,0"/>
          </Grid>
        </Border>
        <Border Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource BorderBrush}"
                BorderThickness="1" CornerRadius="12" Padding="14">
          <StackPanel>
            <TextBlock Text="音声を検出するアプリ" FontSize="13" FontWeight="SemiBold"/>
            <Grid Margin="0,7,0,13">
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <ComboBox x:Name="AppBox" Grid.Column="0" DisplayMemberPath="Display" SelectedValuePath="ProcessName"/>
              <Button x:Name="RefreshApps" Grid.Column="1" Content="更新" Margin="8,0,0,0"/>
            </Grid>
            <TextBlock Text="対象の出力デバイス名 (空欄ですべて)" FontSize="12"/>
            <TextBox x:Name="DeviceBox" Margin="0,6,0,13"/>
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <StackPanel Grid.Column="0" Margin="0,0,6,0">
                <TextBlock Text="余韻時間 (秒)"/>
                <TextBox x:Name="LingerBox" Margin="0,5,0,10"/>
                <TextBlock Text="音量 (%)"/>
                <TextBox x:Name="AmplitudeBox" Margin="0,5,0,10"/>
              </StackPanel>
              <StackPanel Grid.Column="1" Margin="6,0,0,0">
                <TextBlock Text="周波数 (Hz)"/>
                <TextBox x:Name="FrequencyBox" Margin="0,5,0,10"/>
                <TextBlock Text="検出しきい値"/>
                <TextBox x:Name="ThresholdBox" Margin="0,5,0,10"/>
              </StackPanel>
            </Grid>
            <CheckBox x:Name="AutostartBox" Content="Windowsログイン時に起動 (トレイに収納)" Margin="0,1,0,12"/>
            <Button x:Name="SaveButton" Content="設定を保存"/>
          </StackPanel>
        </Border>
        <Expander x:Name="ConsoleExpander" Header="  Console / 動作履歴" Margin="0,14,0,0">
          <Border Background="{DynamicResource CardBrush}" Padding="8" CornerRadius="9" Margin="0,8,0,0">
            <TextBox x:Name="ConsoleBox" Height="160" FontFamily="Consolas" FontSize="11"
                     IsReadOnly="True" TextWrapping="NoWrap" VerticalScrollBarVisibility="Auto"
                     HorizontalScrollBarVisibility="Auto"/>
          </Border>
        </Expander>
        <TextBlock Text="× でトレイに収納・トレイメニューから終了" Foreground="{DynamicResource SubtleBrush}"
                   HorizontalAlignment="Center" FontSize="11" Margin="0,14,0,6"/>
      </StackPanel>
    </ScrollViewer>
  </Grid>
</Window>
'@

try {
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $script:window = [Windows.Markup.XamlReader]::Load($reader)
    $script:themeBox = $script:window.FindName('ThemeBox')
    $script:appBox = $script:window.FindName('AppBox')
    $script:deviceBox = $script:window.FindName('DeviceBox')
    $script:lingerBox = $script:window.FindName('LingerBox')
    $script:frequencyBox = $script:window.FindName('FrequencyBox')
    $script:amplitudeBox = $script:window.FindName('AmplitudeBox')
    $script:thresholdBox = $script:window.FindName('ThresholdBox')
    $script:autostartBox = $script:window.FindName('AutostartBox')
    $script:statusText = $script:window.FindName('StatusText')
    $script:toggleButton = $script:window.FindName('ToggleButton')
    $script:consoleBox = $script:window.FindName('ConsoleBox')
    $script:consoleExpander = $script:window.FindName('ConsoleExpander')

    $script:tray = New-Object System.Windows.Forms.NotifyIcon
    $script:tray.Icon = [System.Drawing.SystemIcons]::Application
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $showItem = $menu.Items.Add('ウィンドウを表示')
    $monitorItem = $menu.Items.Add('監視を開始/停止')
    $quitItem = $menu.Items.Add('終了')
    $script:tray.ContextMenuStrip = $menu
    $script:tray.Visible = $true

    $settings = Read-KeeperSettings
    $script:deviceBox.Text = $settings.DeviceName
    $script:lingerBox.Text = $settings.LingerSeconds
    $script:frequencyBox.Text = $settings.Frequency
    $script:amplitudeBox.Text = $settings.Amplitude
    $script:thresholdBox.Text = $settings.Threshold
    Refresh-AppList $settings.AppName
    $script:autostartBox.IsChecked = (Test-Path -LiteralPath $script:startupItem) -or (Test-Path -LiteralPath $script:legacyStartupItem)
    $theme = Get-GuiTheme
    $script:themeBox.SelectedIndex = if ($theme -eq 'Light') { 1 } else { 0 }
    Apply-Theme $theme

    $script:themeBox.Add_SelectionChanged({
        if ($null -eq $script:window) { return }
        $t = if ($script:themeBox.SelectedIndex -eq 1) { 'Light' } else { 'Dark' }
        Apply-Theme $t
        Save-GuiTheme $t
    })

    $script:window.FindName('RefreshApps').Add_Click({
        Refresh-AppList ([string]$script:appBox.SelectedValue)
    })

    $script:window.FindName('SaveButton').Add_Click({
        try {
            $values = @{}
            $inv = [System.Globalization.CultureInfo]::InvariantCulture
            foreach ($entry in @(
                @('Frequency', $script:frequencyBox.Text, 1.0, 20000.0),
                @('Amplitude', $script:amplitudeBox.Text, 0.0, 100.0),
                @('LingerSeconds', $script:lingerBox.Text, 0.0, 3600.0),
                @('Threshold', $script:thresholdBox.Text, 0.0, 1.0)
            )) {
                $n = 0.0
                if (-not [double]::TryParse([string]$entry[1], [System.Globalization.NumberStyles]::Float, $inv, [ref]$n) -or
                    [double]::IsNaN($n) -or [double]::IsInfinity($n) -or $n -lt $entry[2] -or $n -gt $entry[3]) {
                    throw ('Invalid value: ' + $entry[0])
                }
                $values[$entry[0]] = $n.ToString($inv)
            }
            $values['DeviceName'] = $script:deviceBox.Text.Trim()
            $values['AppName'] = [string]$script:appBox.SelectedValue
            Set-Startup ([bool]$script:autostartBox.IsChecked)
            Write-KeeperSettings $values
            [System.Windows.MessageBox]::Show('設定を保存しました。', 'NZXT Relay Keeper') | Out-Null
        } catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message, '設定エラー') | Out-Null
        }
    })

    $script:toggleButton.Add_Click({
        if (Is-Monitoring) { Stop-Monitoring } else { Start-Monitoring }
    })
    $showItem.add_Click({ $script:window.Show(); $script:window.Activate() | Out-Null })
    $script:tray.add_DoubleClick({ $script:window.Show(); $script:window.Activate() | Out-Null })
    $monitorItem.add_Click({ if (Is-Monitoring) { Stop-Monitoring } else { Start-Monitoring } })
    $quitItem.add_Click({
        $script:exiting = $true
        $script:window.Close()
    })
    $script:window.Add_Closing({
        param($sender, $e)
        if (-not $script:exiting) {
            $e.Cancel = $true
            $script:window.Hide()
        }
    })

    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(900)
    $timer.Add_Tick({ Update-Status; if ($script:consoleExpander.IsExpanded) { Update-Log } })
    $timer.Start()
    Start-Monitoring
    Update-Log
    if ($Minimized) { $script:window.Add_ContentRendered({ $script:window.Hide() }) }
    $script:application = New-Object System.Windows.Application
    $script:application.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose
    [void]$script:application.Run($script:window)
} finally {
    if ($null -ne $timer) { $timer.Stop() }
    try { Stop-Monitoring } catch { }
    if ($null -ne $script:tray) { $script:tray.Visible = $false; $script:tray.Dispose() }
    $script:mutex.ReleaseMutex()
    $script:mutex.Dispose()
}
