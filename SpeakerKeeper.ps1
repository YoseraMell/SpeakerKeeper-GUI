# ============================================================
#  SpeakerKeeper
#  他のアプリ(ブラウザ・ゲームなど)から音が出ている間だけ
#  SoundKeeper で小さなサイン波を流し、スピーカーのオートスリープを防ぐ。
#  音が止まってから「余韻時間」が過ぎたら SoundKeeper を止める。
#
#  設定は同じフォルダの settings.txt で変更できます(保存すると自動で反映)。
# ============================================================

$ErrorActionPreference = 'Stop'
$scriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$settingsPath = Join-Path $scriptDir 'settings.txt'

# ---- 二重起動防止 ----
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\SpeakerKeeper_SingleInstance', [ref]$createdNew)
if (-not $createdNew) {
    Write-Host 'SpeakerKeeper はすでに起動しています。'
    exit
}

# ---- Windowsの音声セッション(アプリごとの音量メーター)を読むための部品 ----
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace SpeakerKeeperAudio
{
    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator
    {
        int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice
    {
        int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
        int OpenPropertyStore(int stgmAccess, out IPropertyStore store);
    }

    [StructLayout(LayoutKind.Sequential)]
    struct PropertyKey
    {
        public Guid fmtid;
        public int pid;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct PropVariant
    {
        public ushort vt;
        public ushort r1, r2, r3;
        public IntPtr p1;
        public IntPtr p2;
    }

    [ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore
    {
        int GetCount(out int count);
        int GetAt(int index, out PropertyKey key);
        int GetValue(ref PropertyKey key, out PropVariant value);
    }

    [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionManager2
    {
        int GetAudioSessionControl(IntPtr sessionGuid, int streamFlags, out IntPtr sessionControl);
        int GetSimpleAudioVolume(IntPtr sessionGuid, int streamFlags, out IntPtr audioVolume);
        int GetSessionEnumerator(out IAudioSessionEnumerator sessionEnum);
    }

    [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionEnumerator
    {
        int GetCount(out int count);
        int GetSession(int index, [MarshalAs(UnmanagedType.IUnknown)] out object session);
    }

    [ComImport, Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionControl2
    {
        // IAudioSessionControl
        int GetState(out int state);
        int GetDisplayName(IntPtr name);
        int SetDisplayName(IntPtr name, IntPtr ctx);
        int GetIconPath(IntPtr path);
        int SetIconPath(IntPtr path, IntPtr ctx);
        int GetGroupingParam(IntPtr param);
        int SetGroupingParam(IntPtr param, IntPtr ctx);
        int RegisterAudioSessionNotification(IntPtr client);
        int UnregisterAudioSessionNotification(IntPtr client);
        // IAudioSessionControl2
        int GetSessionIdentifier(IntPtr id);
        int GetSessionInstanceIdentifier(IntPtr id);
        int GetProcessId(out uint pid);
    }

    [ComImport, Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioMeterInformation
    {
        int GetPeakValue(out float peak);
    }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    class MMDeviceEnumeratorCom { }

    public static class Meter
    {
        [DllImport("ole32.dll")]
        static extern int PropVariantClear(ref PropVariant pvar);

        // 今の既定の出力デバイスの名前(例: スピーカー (Realtek(R) Audio))を返す
        public static string GetDefaultDeviceName()
        {
            object enumObj = new MMDeviceEnumeratorCom();
            IMMDeviceEnumerator enumerator = (IMMDeviceEnumerator)enumObj;
            IMMDevice device = null;
            IPropertyStore store = null;
            try
            {
                if (enumerator.GetDefaultAudioEndpoint(0, 1, out device) != 0 || device == null) return "";
                if (device.OpenPropertyStore(0 /* STGM_READ */, out store) != 0 || store == null) return "";
                PropertyKey key = new PropertyKey();
                key.fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"); // PKEY_Device_FriendlyName
                key.pid = 14;
                PropVariant v;
                if (store.GetValue(ref key, out v) != 0) return "";
                string name = (v.vt == 31 /* VT_LPWSTR */) ? Marshal.PtrToStringUni(v.p1) : "";
                PropVariantClear(ref v);
                return name ?? "";
            }
            finally
            {
                if (store != null) Marshal.ReleaseComObject(store);
                if (device != null) Marshal.ReleaseComObject(device);
                Marshal.ReleaseComObject(enumObj);
            }
        }

        // 指定したプロセスID以外のアプリが出している音の最大レベル(0〜1)を返す
        public static float GetOtherAppsPeak(HashSet<uint> excludePids)
        {
            float max = 0f;
            object enumObj = new MMDeviceEnumeratorCom();
            IMMDeviceEnumerator enumerator = (IMMDeviceEnumerator)enumObj;
            IMMDevice device = null;
            object mgrObj = null;
            IAudioSessionEnumerator sessions = null;
            try
            {
                // 0 = eRender(再生), 1 = eMultimedia
                if (enumerator.GetDefaultAudioEndpoint(0, 1, out device) != 0 || device == null) return 0f;
                Guid iid = typeof(IAudioSessionManager2).GUID;
                if (device.Activate(ref iid, 23 /* CLSCTX_ALL */, IntPtr.Zero, out mgrObj) != 0) return 0f;
                IAudioSessionManager2 mgr = (IAudioSessionManager2)mgrObj;
                if (mgr.GetSessionEnumerator(out sessions) != 0 || sessions == null) return 0f;

                int count;
                sessions.GetCount(out count);
                for (int i = 0; i < count; i++)
                {
                    object s = null;
                    try
                    {
                        sessions.GetSession(i, out s);
                        if (s == null) continue;
                        uint pid = 0;
                        IAudioSessionControl2 ctl = s as IAudioSessionControl2;
                        if (ctl != null) ctl.GetProcessId(out pid);
                        if (excludePids.Contains(pid)) continue;
                        IAudioMeterInformation meter = s as IAudioMeterInformation;
                        if (meter == null) continue;
                        float p;
                        if (meter.GetPeakValue(out p) == 0 && p > max) max = p;
                    }
                    catch { }
                    finally
                    {
                        if (s != null && Marshal.IsComObject(s)) Marshal.ReleaseComObject(s);
                    }
                }
            }
            finally
            {
                if (sessions != null) Marshal.ReleaseComObject(sessions);
                if (mgrObj != null && Marshal.IsComObject(mgrObj)) Marshal.ReleaseComObject(mgrObj);
                if (device != null) Marshal.ReleaseComObject(device);
                Marshal.ReleaseComObject(enumObj);
            }
            return max;
        }
    }
}
'@

# ---- 設定の読み込み ----
function Read-Settings {
    $s = @{
        Frequency     = 300
        Amplitude     = 0.1
        LingerSeconds = 30
        Threshold     = 0.001
        SoundKeeper   = 'SoundKeeper64.exe'
        DeviceName    = ''
    }
    if (Test-Path $settingsPath) {
        foreach ($line in Get-Content -Path $settingsPath -Encoding UTF8) {
            $t = $line.Trim()
            if ($t -eq '' -or $t.StartsWith('#')) { continue }
            $kv = $t -split '=', 2
            if ($kv.Count -ne 2) { continue }
            $key = $kv[0].Trim(); $val = $kv[1].Trim()
            if (-not $s.ContainsKey($key)) { continue }
            if ($key -eq 'SoundKeeper' -or $key -eq 'DeviceName') { $s[$key] = $val; continue }
            $num = 0.0
            if ([double]::TryParse($val, [System.Globalization.NumberStyles]::Float,
                                   [System.Globalization.CultureInfo]::InvariantCulture, [ref]$num)) {
                $s[$key] = $num
            } else {
                Write-Host "settings.txt の $key の値が読めません: $val (初期値を使います)"
            }
        }
    }
    $exe = $s.SoundKeeper
    if (-not [System.IO.Path]::IsPathRooted($exe)) { $exe = Join-Path $scriptDir $exe }
    $s.SoundKeeperPath = $exe
    return $s
}

function Get-Inv([double]$v) { $v.ToString([System.Globalization.CultureInfo]::InvariantCulture) }

$keeperProc = $null

function Start-Keeper($s) {
    if (-not (Test-Path $s.SoundKeeperPath)) {
        Write-Host "SoundKeeper が見つかりません: $($s.SoundKeeperPath)"
        return $null
    }
    $argLine = "sine -f $(Get-Inv $s.Frequency) -a $(Get-Inv $s.Amplitude)"
    $p = Start-Process -FilePath $s.SoundKeeperPath -ArgumentList $argLine -WindowStyle Hidden -PassThru
    Write-Host ("{0:HH:mm:ss}  音を検出 → SoundKeeper 開始 ({1})" -f (Get-Date), $argLine)
    return $p
}

function Stop-Keeper([string]$reason) {
    if ($script:keeperProc -ne $null) {
        try { if (-not $script:keeperProc.HasExited) { $script:keeperProc.Kill() } } catch { }
        $script:keeperProc = $null
        Write-Host ("{0:HH:mm:ss}  {1} → SoundKeeper 停止" -f (Get-Date), $reason)
    }
}

# ---- メインループ ----
$settings  = Read-Settings
$settingsTime = if (Test-Path $settingsPath) { (Get-Item $settingsPath).LastWriteTime } else { $null }
$lastSound = [datetime]::MinValue
$myPid     = [uint32]$PID

Write-Host 'SpeakerKeeper 起動しました。'
Write-Host ("  音: {0}Hz / {1}%   余韻: {2}秒   検出しきい値: {3}" -f `
    (Get-Inv $settings.Frequency), (Get-Inv $settings.Amplitude), $settings.LingerSeconds, (Get-Inv $settings.Threshold))
if ($settings.DeviceName -ne '') {
    Write-Host ("  対象デバイス: 名前に「{0}」を含む出力先のときだけ動作" -f $settings.DeviceName)
} else {
    Write-Host '  対象デバイス: 指定なし(どの出力先でも動作)'
}
Write-Host '  (このウィンドウを閉じると終了します)'
$lastDevice = $null

try {
    while ($true) {
        # 設定ファイルが保存し直されたら読み込み直す
        if (Test-Path $settingsPath) {
            $t = (Get-Item $settingsPath).LastWriteTime
            if ($t -ne $settingsTime) {
                $settingsTime = $t
                $settings = Read-Settings
                Write-Host ("{0:HH:mm:ss}  settings.txt を読み込み直しました ({1}Hz / {2}% / 余韻 {3}秒)" -f `
                    (Get-Date), (Get-Inv $settings.Frequency), (Get-Inv $settings.Amplitude), $settings.LingerSeconds)
                Stop-Keeper '設定変更'
            }
        }

        # 今の出力先が対象デバイスか確認(ヘッドホンなどに切り替えたら止める)
        $device = ''
        try { $device = [SpeakerKeeperAudio.Meter]::GetDefaultDeviceName() } catch { $device = '' }
        if ($device -ne $lastDevice) {
            $lastDevice = $device
            Write-Host ("{0:HH:mm:ss}  現在の出力先: {1}" -f (Get-Date), $device)
        }
        $isTarget = ($settings.DeviceName -eq '') -or $device.Contains($settings.DeviceName)
        if (-not $isTarget) {
            Stop-Keeper '対象外のデバイスに切り替わった'
            $lastSound = [datetime]::MinValue
            Start-Sleep -Milliseconds 500
            continue
        }

        # SoundKeeper 自身とこのスクリプトの音は除外して測る
        $exclude = New-Object 'System.Collections.Generic.HashSet[uint32]'
        [void]$exclude.Add($myPid)
        foreach ($p in Get-Process -Name 'SoundKeeper*' -ErrorAction SilentlyContinue) { [void]$exclude.Add([uint32]$p.Id) }

        $peak = 0
        try { $peak = [SpeakerKeeperAudio.Meter]::GetOtherAppsPeak($exclude) } catch { $peak = 0 }

        $now = Get-Date
        if ($peak -gt $settings.Threshold) {
            $lastSound = $now
            if ($keeperProc -eq $null -or $keeperProc.HasExited) {
                $keeperProc = Start-Keeper $settings
            }
        }
        elseif ($keeperProc -ne $null -and ($now - $lastSound).TotalSeconds -ge $settings.LingerSeconds) {
            Stop-Keeper ("無音が {0} 秒続いた" -f $settings.LingerSeconds)
        }

        Start-Sleep -Milliseconds 250
    }
}
finally {
    Stop-Keeper '終了'
    $mutex.ReleaseMutex()
}
