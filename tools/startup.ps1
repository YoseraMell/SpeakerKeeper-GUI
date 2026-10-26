param([ValidateSet('add','remove')][string]$Mode)

$root     = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$main     = Join-Path $root 'SpeakerKeeper.ps1'
$lnkPath  = Join-Path ([Environment]::GetFolderPath('Startup')) 'SpeakerKeeper.lnk'

if ($Mode -eq 'add') {
    $sh  = New-Object -ComObject WScript.Shell
    $lnk = $sh.CreateShortcut($lnkPath)
    $lnk.TargetPath       = 'powershell.exe'
    $lnk.Arguments        = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$main`""
    $lnk.WorkingDirectory = $root
    $lnk.WindowStyle      = 7
    $lnk.Save()
    # 今すぐ裏で起動(すでに起動中なら何もしない)
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$main`"" -WindowStyle Hidden
    Write-Host 'スタートアップに登録し、裏で起動しました。次回からはPC起動時に自動で動きます。'
}
else {
    Remove-Item $lnkPath -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.CommandLine -like '*SpeakerKeeper.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Get-Process -Name 'SoundKeeper*' -ErrorAction SilentlyContinue | Stop-Process -Force
    Write-Host 'スタートアップから削除し、停止しました。'
}
