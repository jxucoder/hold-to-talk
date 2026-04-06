<p align="center">
  <img src="Resources/logo.png" width="128" alt="Hold To Talk logo">
</p>

<h1 align="center">Hold To Talk</h1>

<p align="center">Free, open-source voice dictation for macOS. Hold a key, speak, release -- your words appear wherever your cursor is. Everything runs locally on your Mac.</p>

<p align="center">
  <a href="https://jxucoder.github.io/hold-to-talk/demo.mp4">
    <img src="Resources/demo.gif" width="680" alt="Hold to Talk demo">
  </a>
</p>

<p align="center">
  <a href="https://jxucoder.github.io/hold-to-talk/">Website</a>
  ·
  <a href="https://jxucoder.github.io/hold-to-talk/demo.mp4">Watch the demo video</a>
</p>

- **Free and open-source** -- no subscription, no paywall. Inspect the code, build it yourself, or install a signed release.
- **Local and private** -- powered by [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) + [NVIDIA Parakeet TDT 0.6B](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2). No cloud APIs, no accounts, no tracking.
- **Fast** -- optimized for low-latency dictation with an int8-quantized on-device speech model.
- **Works everywhere** -- dictate into any app: Slack, Notes, your IDE, email, browser.
- **Apple Intelligence cleanup** (optional) -- on-device grammar and filler-word removal. Requires macOS 26+.
- **Auto-updates** -- direct downloads update in-app via [Sparkle](https://sparkle-project.org).
- **Stays out of your way** -- lives in your menu bar. Hold a key to record, release to paste.

## Install

**Requirements:** macOS 15+, Apple Silicon.

### Download

Grab the latest notarized `DMG` or `ZIP` from [GitHub Releases](https://github.com/jxucoder/hold-to-talk/releases), install into `/Applications`, and open.

### Homebrew

```bash
brew install jxucoder/tap/holdtotalk
```

### First launch

On first launch, Hold to Talk guides you through:

1. Granting **Microphone**, **Accessibility**, and **Input Monitoring** permissions
2. Downloading the Parakeet TDT speech model (~640 MB, one-time)
3. Choosing your hotkey

### Build from source

Requires Xcode command line tools.

```bash
git clone https://github.com/jxucoder/hold-to-talk.git
cd hold-to-talk
make build          # downloads sherpa-onnx, builds release, assembles .app
make install        # copies to /Applications
make run            # debug build + run

make test-reset     # full uninstall + reset all state + reset permissions
```

## Usage

1. Launch -- appears in menu bar as a mic icon
2. Hold **Ctrl** (default) to record
3. Release to transcribe and insert into the active window
4. Click the menu bar icon for status and settings

### Settings

| Setting | Default | Options |
|---|---|---|
| Hotkey | Control | Control, Option, Shift, Right Option |
| Transcription profile | Balanced | Fast, Balanced, Best |
| Text cleanup | On (if available) | On/Off -- Apple Intelligence, macOS 26+ |
| Cleanup prompt | (default) | Customizable instructions |
| Launch at Login | Off | On/Off |
| Diagnostic logging | Off | On/Off -- local only, transcript text redacted |

## Architecture

```
HoldToTalkApp       SwiftUI menu bar app, entry point
DictationEngine     Orchestrator: record -> transcribe -> cleanup -> insert
AudioRecorder       AVAudioEngine mic capture, resamples to 16 kHz mono
Transcriber         sherpa-onnx offline recognizer + Silero VAD segmentation
TextCleanup         Optional on-device cleanup via Apple Intelligence (macOS 26+)
TextInserter        CGEvent unicode insertion or clipboard paste (per-app strategy)
HotkeyManager       NSEvent global/local monitor for modifier keys
ModelManager        Parakeet TDT model download and lifecycle
RecordingHUD        Floating overlay with live waveform during recording
OnboardingView      Guided setup: permissions, model download, hotkey test
SettingsView        SwiftUI settings form
```

Dependencies: [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) (speech recognition), [Sparkle](https://sparkle-project.org) (auto-updates, excluded from App Store builds).

### Why Parakeet TDT + sherpa-onnx

**[NVIDIA Parakeet TDT 0.6B](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2)** uses a Token-and-Duration Transducer architecture instead of the encoder-decoder attention approach used by Whisper. Key advantages for real-time dictation:

- **Linear latency** -- TDT predicts tokens frame-by-frame without an autoregressive decoding loop, so transcription time scales linearly with audio length rather than quadratically.
- **Silence-robust** -- emits blanks for non-speech frames instead of hallucinating text, a common problem with Whisper on silence or noise.
- **Compact** -- int8-quantized to ~150 MB on disk (vs ~1.5 GB for Whisper Large-v3) while matching or exceeding its English accuracy.
- **Greedy search is sufficient** -- no beam search needed for high-quality output, reducing CPU cost.

**[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)** provides the inference runtime as a single C library with Swift interop:

- Mel spectrogram extraction matched to Parakeet's training configuration (128-dim log-mel features)
- TDT transducer decoding with blank penalty and optional modified beam search for hotword boosting
- Bundled [Silero VAD](https://github.com/snakers4/silero-vad) for speech segmentation, preventing transducer looping on long audio
- Multi-threaded CPU inference with configurable thread counts

This combination lets the app focus on UX (hotkey management, text insertion, recording HUD) while sherpa-onnx handles the entire audio-to-text pipeline locally.

## Permissions

macOS will prompt for:
- **Microphone** -- recording audio
- **Accessibility** (Keyboard Access) -- inserting text into apps
- **Input Monitoring** -- detecting the global hotkey

## Notes

- Secure text fields (password inputs) are intentionally blocked.
- Direct downloads support in-app updates via Sparkle. App Store builds use App Store distribution.

## Contributing

Contributions welcome. Please open an issue to discuss larger changes before submitting a PR.

## Privacy

Everything runs on your Mac. No cloud transcription, no accounts, no tracking. Diagnostic logs are off by default, local only, and redact transcript text. See [Privacy Policy](PRIVACY.md).

## License

[Apache 2.0](LICENSE)
