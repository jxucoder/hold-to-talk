# OpenMumble

Local-first voice dictation for macOS (and Linux). Hold a key, speak, release — your words appear in the active window, cleaned up by AI.

**Stack:**

- **Whisper** (via [faster-whisper](https://github.com/SYSTRAN/faster-whisper)) — runs locally, no cloud, sub-second latency on Apple Silicon
- **Claude API** (optional) — removes filler words, fixes grammar, resolves self-corrections ("Tuesday no Wednesday" → "Wednesday")
- **Push-to-talk** — hold a hotkey to record, release to transcribe and paste

## Quick start

```bash
# Clone and install
git clone https://github.com/jxucoder/openmumble.git
cd openmumble
pip install -e .

# (Optional) Set your Anthropic API key for Claude cleanup
export ANTHROPIC_API_KEY="sk-ant-..."

# Run
openmumble
```

Hold **Ctrl** (default hotkey) to record, release to transcribe. Text is pasted into whatever window is focused.

## Configuration

Copy `config.example.yaml` to `config.yaml` and edit:

```yaml
anthropic_api_key: ""          # or set ANTHROPIC_API_KEY env var
claude_model: "claude-sonnet-4-20250514"

whisper:
  model_size: "small.en"       # tiny.en, base.en, small.en, medium, large-v3
  device: "auto"
  compute_type: "int8"

audio:
  sample_rate: 16000
  channels: 1

hotkey: "ctrl"                 # ctrl, alt, shift, cmd, or any single character
enable_cleanup: true           # set false to skip Claude and use raw Whisper output
```

### CLI overrides

```bash
openmumble --model large-v3 --hotkey alt
openmumble --no-cleanup        # raw Whisper output, no Claude
openmumble -c /path/to/config.yaml
```

### Environment variables

| Variable | Overrides |
|---|---|
| `ANTHROPIC_API_KEY` | `anthropic_api_key` |
| `OPENMUMBLE_MODEL` | `whisper.model_size` |
| `OPENMUMBLE_HOTKEY` | `hotkey` |

## How it works

1. **Hold hotkey** → microphone starts recording
2. **Release hotkey** → recording stops, audio sent to local Whisper model
3. **Whisper transcribes** → raw text extracted (runs entirely on your machine)
4. **Claude cleans up** (optional) → filler words removed, grammar fixed, self-corrections resolved
5. **Text pasted** → result copied to clipboard and pasted into the active window

## Requirements

- Python 3.10+
- macOS: works out of the box (pbcopy + AppleScript for paste)
- Linux: needs `xclip` and `xdotool` (`sudo apt install xclip xdotool`)
- A microphone
- (Optional) Anthropic API key for Claude cleanup

## License

Apache 2.0
