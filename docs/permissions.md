# Permission System (macOS)

This app uses three macOS privacy permissions:

1. `Microphone` (`kTCCServiceMicrophone`)
2. `Accessibility` (`kTCCServiceAccessibility`)
3. `Input Monitoring` (`kTCCServiceListenEvent`)

## How Detection Works

Current checks are done in code (on launch, in onboarding, and when app becomes active):

- Microphone: `AVCaptureDevice.authorizationStatus(for: .audio)`
- Accessibility: `AXIsProcessTrusted()`
- Input Monitoring: `CGPreflightListenEventAccess()`

Prompt APIs:

- Microphone: `AVCaptureDevice.requestAccess(for: .audio)`
- Accessibility: `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`
- Input Monitoring: `CGRequestListenEventAccess()`

## Important macOS Limitation

The app **cannot** silently add itself to Input Monitoring or Accessibility.
Only macOS can grant these permissions after user approval in system UI.

So the correct UX is:

1. trigger prompt API
2. open exact System Settings pane if still not granted
3. poll/re-check state and auto-greenify once macOS applies approval

## Clean User Test (from scratch)

Use this sequence to test onboarding exactly as a first-time user:

1. Install app into `/Applications`:
   - `make install`
2. Reset app-specific TCC permissions:
   - `make permissions-reset`
3. Optionally clear app prefs:
   - `defaults delete com.holdtotalk.app 2>/dev/null || true`
4. Launch from `/Applications/HoldToTalk.app`

## Why `/Applications` Matters

macOS privacy entries are tied to the signed app identity and path context.
Running from random build folders can create confusing permission behavior.
For reliable user-like testing, always launch from `/Applications`.
