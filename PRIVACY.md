# Privacy Policy

**Effective date:** March 8, 2026

This privacy policy covers the Hold to Talk macOS app and the Hold to Talk website at `holdtotalk.ai`.

## Summary

- The **app** is designed to keep dictation data on your Mac.
- The **website** uses Google Analytics to understand traffic and page usage.
- Hold to Talk does **not** sell personal data or use advertising trackers inside the app.

## Hold to Talk app

### What the app does with your data

Hold to Talk records microphone audio only while you hold the dictation hotkey. Speech recognition runs locally on your Mac using on-device models. Audio and transcribed text are not sent to Hold to Talk servers.

### Audio

- Microphone audio is captured only during an active dictation session.
- Audio is processed locally in memory for transcription.
- Audio is not uploaded to Hold to Talk.
- Audio is not stored as recordings by Hold to Talk.

### Transcriptions

- Transcribed text is inserted into the app you are using.
- Hold to Talk does not keep a cloud transcription history.
- If optional Apple Intelligence cleanup is enabled, cleanup is performed by on-device system features provided by macOS.
- If you explicitly enable local diagnostic logging for troubleshooting, transcript text is redacted in those logs by default.

### Local storage

Hold to Talk stores app data on your Mac, including:

- preferences such as hotkey choice, selected model, and cleanup settings
- downloaded speech models required for on-device transcription
- temporary app state needed for onboarding and operation
- optional local diagnostic logs, only if you enable them for troubleshooting

Hold to Talk does not intentionally store audio recordings or a server-side transcript history.

### Network activity from the app

The app may make limited network requests for product delivery features:

- downloading speech models from supported model hosts such as Hugging Face
- checking for direct-release app updates through Sparkle when using the non-App-Store version

These requests are used to download app or model files. Hold to Talk does not send your microphone audio or transcription text as part of those requests.

### App analytics and tracking

Hold to Talk does not include in-app advertising, third-party analytics SDKs, or app telemetry that tracks what you dictate.

## Website

### Website analytics

The Hold to Talk website uses **Google Analytics** to measure site traffic and usage. When you visit the website, Google Analytics may collect information such as:

- pages viewed
- approximate geographic region
- browser and device information
- referral source
- basic interaction and session data

This information helps understand website usage and improve the site. Website analytics do not include your dictation audio or transcription text from the app.

### Website hosting and downloads

The website and release assets may be served through third-party infrastructure such as GitHub Pages, GitHub Releases, and other download providers. Those services may receive technical information such as your IP address, user agent, and request logs as part of normal web delivery.

## Permissions

The app may request these macOS permissions:

- **Microphone** for voice input
- **Accessibility** for text insertion and interaction support
- **Input Monitoring** for reliable global hotkey detection

These permissions are managed by macOS and can be revoked at any time in System Settings.

## Third parties

Depending on how you use Hold to Talk, third-party services may be involved:

- **Google Analytics** for website traffic analytics
- **GitHub** for website hosting, source code, and release downloads
- **Hugging Face** for speech model downloads
- **Sparkle** for direct-release update delivery

Their handling of technical request data is governed by their own policies.

## Children

Hold to Talk is not directed to children, and Hold to Talk does not knowingly collect personal information from children through the app.

## Changes to this policy

If this policy changes, the updated version will be posted on the website and in this repository with a new effective date.

## Contact

If you have privacy questions, open an issue at:

`https://github.com/jxucoder/hold-to-talk/issues`
