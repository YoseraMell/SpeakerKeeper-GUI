# SpeakerKeeper

English | [日本語](README_jp.md)

A small Windows tool for PC speakers that go to sleep automatically during silence.

Some powered speakers go to sleep as soon as their input falls below a certain level, then fade back in when sound returns. As a result, audio can sound muffled or dull at the start of a video or after a quiet scene.

SpeakerKeeper uses [SoundKeeper](https://veg.by/projects/soundkeeper) to play a quiet sine wave **only while other apps (browsers, games, etc.) are playing audio**, which keeps the speakers awake. Once the other audio stops, it waits for a configurable time and then stops the sine wave too.

## Features

- Watches other apps' audio meters and plays the sine wave only while they make sound (SoundKeeper's own output is ignored)
- Keeps playing for a set number of seconds after audio stops (linger time)
- Runs only on a specified output device (stops automatically when you switch to headphones, etc.)
- Edit and save `settings.txt` to apply changes, even while it's running
- Nothing extra to install (runs on the PowerShell built into Windows)

## Requirements

- Windows 10 / 11
- [SoundKeeper](https://veg.by/projects/soundkeeper) (download separately)

## Installation

1. Download and extract this repository (green **Code** button → **Download ZIP**)
2. Download `soundkeeper.7z` from the [SoundKeeper website](https://veg.by/projects/soundkeeper)
3. Copy **`SoundKeeper64.exe`** from the archive into the same folder as `SpeakerKeeper.ps1`
   - Do not rename it (don't add `Sine` or other options to the name)
4. If you already have SoundKeeper in your startup folder, remove it and close it

## Usage

| File | What it does |
|---|---|
| `1_test_run.bat` | Runs in a visible window, for testing and tuning settings. Close the window to stop |
| `2_add_to_startup.bat` | Adds it to startup and starts it in the background right away. From then on it starts automatically at sign-in |
| `3_remove_from_startup.bat` | Removes it from startup and stops it |

Run `1_test_run.bat` first. When you play audio it should show "SoundKeeper 開始" (started), and after the linger time it should show "停止" (stopped).

> If you move the folder, run `2_add_to_startup.bat` again.

> Console messages are in Japanese.

## Settings

Open `settings.txt` in Notepad, change the values, and save.

| Key | Default | Description |
|---|---|---|
| `Frequency` | `300` | Tone frequency (Hz) |
| `Amplitude` | `0.1` | Tone amplitude (%) |
| `LingerSeconds` | `30` | Seconds to keep playing after other audio stops |
| `Threshold` | `0.001` | Level (0–1) treated as "audio is playing". Raise it if notification sounds trigger it |
| `DeviceName` | (empty) | Only runs while the default output device's name contains this text. Empty = any device |
| `SoundKeeper` | `SoundKeeper64.exe` | SoundKeeper executable name |

The name for `DeviceName` is shown in the `1_test_run.bat` window as "**現在の出力先: ...**" (current output). Example: `Speakers (Realtek(R) Audio)`

### Finding the right tone

Speakers react to different tones.

1. First, check whether the muffling goes away with a clearly audible tone (e.g. `Frequency=1000`, `Amplitude=1`)
   - If it doesn't, the problem is probably not auto-sleep
2. If it does, lower `Amplitude` step by step and try different `Frequency` values to find **the least noticeable setting that still works**

> [!WARNING]
> **If the tone is too quiet, the speakers can't detect it and will still go to sleep.**
> If the muffling comes back after lowering `Amplitude`, raise it a little.
>
> The sine wave's level also **depends on the Windows volume**. Lowering the Windows volume can make the same setting stop working, so keep the Windows volume fairly high and use the speaker's own knob to set a comfortable listening level.
>
> Very low tones (below 20 Hz) or very high tones (around 20 kHz) may not be picked up by the speaker's detection circuit.

## Notes

- On the **first playback after full silence**, the speakers are already asleep, so the fade-in at the start remains. What this prevents is sleep during quiet parts of playback and for playback within the linger time
- While SoundKeeper is running, Windows may not go to sleep automatically (this returns to normal once it stops after the linger time)
- People with sensitive hearing may faintly hear the sine wave in a quiet room
- This is a personal tool, provided without warranty or support

## How it works

- Every 0.25 seconds, it reads each app's audio meter on the default output device using the Windows audio session API (WASAPI / Core Audio)
- It ignores its own process and SoundKeeper's processes
- When it detects audio, it starts `SoundKeeper64.exe sine -f <frequency> -a <amplitude>`, and to stop, it ends that process
- It makes no network connections and writes no files (except the shortcut created when adding it to startup)

The `.bat` files only run `SpeakerKeeper.ps1` with `powershell -ExecutionPolicy Bypass`. You can check their contents in any text editor.

## Credits

The sine wave is played by [SoundKeeper](https://veg.by/projects/soundkeeper) by Evgeny Vrublevsky. SoundKeeper is not included in this repository.

## License

[MIT License](LICENSE)
