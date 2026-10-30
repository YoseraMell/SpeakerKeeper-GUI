param([ValidateSet('add','remove')][string]$Mode)

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$launcher = Join-Path $root 'Launch-GUI.vbs'
$newShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) 'NZXT Relay Keeper.lnk'
$oldShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) 'SpeakerKeeper.lnk'

if ($Mode -eq 'add') {
    if (-not (Test-Path -LiteralPath $launcher)) { throw 'Launch-GUI.vbs was not found.' }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($newShortcut)
    $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
    $shortcut.Arguments = ('"{0}" --minimized' -f $launcher)
    $shortcut.WorkingDirectory = $root
    $shortcut.Description = 'NZXT Relay Keeper GUI (tray startup)'
    $shortcut.Save()
    Remove-Item -LiteralPath $oldShortcut -Force -ErrorAction SilentlyContinue
    Start-Process -FilePath $shortcut.TargetPath -ArgumentList $shortcut.Arguments -WindowStyle Hidden
    Write-Host 'GUI autostart enabled. The app launches in the tray at user sign-in.'
} else {
    Remove-Item -LiteralPath $newShortcut -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $oldShortcut -Force -ErrorAction SilentlyContinue
    Write-Host 'Autostart removed. To stop a running GUI, choose Exit from its tray menu.'
}
