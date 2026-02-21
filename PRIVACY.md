# Privacy Policy

**Effective date:** February 21, 2026

OpenMumble is a free, open-source voice dictation app for macOS. It is designed from the ground up to keep your data private. This policy explains what the app does — and does not do — with your information.

## Core principle

**Nothing ever leaves your Mac.** All speech recognition and text processing happen entirely on your device using Apple Silicon hardware acceleration. There are no cloud services, user accounts, analytics, or telemetry of any kind.

## Data we collect

None. OpenMumble does not collect, store, transmit, or share any personal data.

## Audio

- Your microphone audio is captured only while you hold the dictation hotkey.
- Audio is processed in memory by [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Core ML) to produce a text transcription.
- Audio is never saved to disk and is discarded immediately after transcription.
- Audio is never sent over the network.

## Transcriptions

- Transcribed text is inserted into the active application and is not retained by OpenMumble.
- If Apple Intelligence cleanup is enabled (macOS 26+), the transcription is processed on-device by the system's built-in language model before insertion. This processing is handled entirely by macOS and does not involve any network requests.

## Network access

OpenMumble makes **no network calls** during normal operation. The only network activity occurs when you download a Whisper speech recognition model for the first time (or switch models). Models are fetched from [Hugging Face](https://huggingface.co/argmaxinc) and stored locally on your Mac. No personal data is transmitted during this download.

## Local storage

OpenMumble stores the following on your Mac:

| Data | Location | Purpose |
|---|---|---|
| User preferences | `UserDefaults` | Hotkey, selected model, cleanup toggle, cleanup prompt |
| Whisper models | App container | On-device speech recognition |

No logs, recordings, transcription history, or usage data are stored.

## macOS permissions

OpenMumble requests two system permissions:

- **Microphone** — to capture audio for voice dictation.
- **Accessibility** — to listen for the global hotkey and simulate keyboard input to paste transcriptions.

These permissions are managed by macOS and can be revoked at any time in System Settings → Privacy & Security.

## Third-party services

OpenMumble has no third-party analytics, crash reporting, advertising, or tracking SDKs. The sole external dependency is [WhisperKit](https://github.com/argmaxinc/WhisperKit), an open-source speech recognition library that runs entirely on-device.

## Children's privacy

OpenMumble does not collect any data from anyone, including children.

## Changes to this policy

If this policy changes, the update will be posted in this repository with a revised effective date.

## Contact

If you have questions about this privacy policy, please [open an issue](https://github.com/jxucoder/openmumble/issues) on GitHub.
