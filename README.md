# OpenMumble

Local-first voice dictation for macOS. Hold a key, speak, release — your words appear in the active window.

- **WhisperKit** — local Whisper on Apple Silicon via Core ML. No cloud, sub-second latency.
- **Claude API** (optional) — cleans up filler words, grammar, self-corrections.
- **Push-to-talk** — hold a modifier key, release to transcribe and paste.
- **Menu bar app** — lives in your menu bar, no dock icon.

## Build

Requires macOS 14+, Apple Silicon, Xcode 15+.

```bash
git clone https://github.com/jxucoder/openmumble.git
cd openmumble
make build
make run
```

Or open `Package.swift` in Xcode and run.

## Usage

1. Launch — appears in menu bar as a mic icon
2. Hold **Ctrl** (default) to record
3. Release to transcribe and paste into the active window
4. Click the menu bar icon for status, last transcription, and settings

### Settings

Open via menu bar → Settings:

| Setting | Default | Options |
|---|---|---|
| Whisper model | `small.en` | `tiny.en`, `base.en`, `small.en`, `medium`, `large-v3` |
| Hotkey | `ctrl` | `ctrl`, `option`, `shift`, `fn`, `right_option` |
| Claude cleanup | on | Toggle + API key |
| Claude model | `claude-sonnet-4-20250514` | Any Anthropic model ID |

Set your Anthropic API key in Settings to enable cleanup. Without it, raw Whisper output is used — the entire pipeline stays offline.

## Architecture

```
OpenMumbleApp          SwiftUI menu bar app, entry point
DictationEngine        Orchestrator: record → transcribe → cleanup → paste
AudioRecorder          AVAudioEngine mic capture, resamples to 16 kHz mono
Transcriber            WhisperKit wrapper, lazy model loading
ClaudeProcessor        Raw URLSession to Anthropic Messages API
TextInserter           NSPasteboard + CGEvent ⌘V simulation
HotkeyManager          NSEvent global/local monitor for modifier keys
SettingsView           SwiftUI settings form
```

One external dependency: [WhisperKit](https://github.com/argmaxinc/WhisperKit). Claude API calls use raw `URLSession` — no SDK.

## Permissions

macOS will prompt for:
- **Microphone** — required for recording
- **Accessibility** — required for global hotkey and paste simulation

## License

Apache 2.0
