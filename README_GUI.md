# NZXT Relay Keeper — Desktop GUI (experimental)

Windows-only compact WPF front end for the existing PowerShell SpeakerKeeper engine.

## Start

1. Keep `SpeakerKeeper-GUI.ps1`, `SpeakerKeeper.ps1`, `settings.txt`, and `Launch-GUI.vbs` in the same folder.
2. Keep a trusted matching `SoundKeeper64.exe` in that folder; the app launches it to emit a tiny sine wave as the existing engine did. The upstream download is https://veg.by/projects/soundkeeper.
3. Double-click **`Launch-GUI.vbs`**. No console window is necessary.
4. Set the output device name to the actual default Windows playback device (e.g., the MiniFuse output device shown in Windows Sound settings), or leave it blank to match any default device.
5. Choose a running app from the app drop-down, or **すべてのアプリ** (All applications). Hit **更新** (Refresh) to reload currently visible running desktop applications.
6. Click **設定を保存** (Save). Engine settings are reloaded automatically. GUI theme preference is saved immediately.

## Controls

- **監視を開始 / 監視を停止** — start and stop audio monitoring.
- **Theme** — ライト (Light), ダーク (Dark), or システム (System), persisted in `%LOCALAPPDATA%\NZXT-Relay-Keeper\gui.json`. System follows the Windows app color mode, including changes while running. Existing Light/Dark preferences are preserved; new preferences default to System.
- **Console / 動作履歴** — expand to see the last 120 logged messages; full persisted log at `%LOCALAPPDATA%\NZXT-Relay-Keeper\SpeakerKeeper.log`.
- **× window button** — hide the window to the notification area; monitoring continues.
- **Tray menu** — show window, toggle monitoring, or fully exit.
- **Windowsログイン時に起動** — create the current-user Startup shortcut. The app starts hidden in the tray on future logins. Saving the setting replaces the old direct-engine Startup shortcut to avoid competing copies.

`2_add_to_startup.bat` also registers and launches the GUI in the tray; `3_remove_from_startup.bat` removes autostart. To stop a *running* GUI after unregistering autostart, use the tray icon's **終了** action.

## App selection semantics

The drop-down contains visible, currently running desktop processes **by process name** (e.g. `chrome`, `spotify`). It does not list every background-only or future process. A remembered process can remain selected when it is not running. Refresh the list when launching a new app.

The PowerShell engine filters Windows audio sessions on the **current default playback device** by that process name. In `settings.txt`, an empty `AppName=` means the previous behavior: audio from any app can trigger SoundKeeper. A selected app must produce sound through the default playback endpoint and expose an audio session with a matching process name to trigger the signal.

## Existing behavior and limitations

- Existing `1_test_run.bat` and direct `SpeakerKeeper.ps1` execution still work. They also read the new optional `AppName` setting.
- When no application audio is detected, the engine stops SoundKeeper after `LingerSeconds`.
- This approach cannot prevent the **very first wake-up fade-in** after a long period of absolute silence; it starts generating the quiet signal *after* detecting other application audio.
- Running SoundKeeper may affect Windows system sleep while the keeper signal is active.
- Exit is graceful during normal operation. Forced termination, crashes, or an existing independently started SoundKeeper instance cannot be guaranteed to clean up.
- The GUI is **experimental** until validated on Windows with the intended speaker and audio interface; code creation alone is not proof of working audio/device behavior.

## Startup and background work

- The saved app selection is available immediately. Running desktop apps are enumerated when the app drop-down is first opened, or when **更新** is clicked.
- Monitoring starts automatically after the first window frame is rendered, including tray startup. Closing and reopening the window does not restart monitoring.
- Logs are loaded when the console is expanded, then refreshed while the window is visible. Tray operation does not poll the log.
- Duplicate launches exit before loading the GUI assemblies. Audio polling checks processes associated with audio sessions instead of enumerating all SoundKeeper processes every 250 ms.

Windows validation checklist: compare launch-to-first-frame time from the same local folder before/after; check normal and `--minimized` launch, saved app selection and Refresh, console reopening after tray use, monitoring stop/show/start, duplicate launch, and tray Exit. Verify default-device switching, all-app/system audio, selected-app audio, and exclusion of independently running SoundKeeper instances. Windows PowerShell and WPF startup costs still apply; no measured speedup is claimed without a Windows comparison.
