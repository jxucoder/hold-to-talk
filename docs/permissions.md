# Permission System (macOS)

This app uses three macOS privacy permissions:

1. `Microphone` (`kTCCServiceMicrophone`)
2. `PostEvent` (`kTCCServicePostEvent`) — appears as "Accessibility" in System Settings
3. `Input Monitoring` (`kTCCServiceListenEvent`)

## How Detection Works

Current checks are done in code (on launch, in onboarding, and when app becomes active):

- Microphone: `AVCaptureDevice.authorizationStatus(for: .audio)`
- PostEvent (keyboard access): `CGPreflightPostEventAccess()`
- Input Monitoring: `CGPreflightListenEventAccess()`

Prompt APIs:

- Microphone: `AVCaptureDevice.requestAccess(for: .audio)`
- PostEvent (keyboard access): `CGRequestPostEventAccess()`
- Input Monitoring: `CGRequestListenEventAccess()`

## Important macOS Limitation

The app **cannot** silently add itself to Input Monitoring or PostEvent.
Only macOS can grant these permissions after user approval in system UI.

So the correct UX is:

1. trigger prompt API
2. open exact System Settings pane if still not granted
3. poll/re-check state and auto-greenify once macOS applies approval

## Why PostEvent Instead of Accessibility

macOS has three separate TCC services under the "Accessibility" umbrella:

- **Accessibility** (`kTCCServiceAccessibility`): Full AXUIElement access. NOT sandbox-compatible.
- **PostEvent** (`kTCCServicePostEvent`): CGEvent posting (keyboard simulation). Sandbox-compatible.
- **ListenEvent** (`kTCCServiceListenEvent`): CGEventTap monitoring. Sandbox-compatible.

This app only needs PostEvent (to type dictated text via CGEvent keyboard simulation)
and ListenEvent (for global hotkey detection). It does NOT use the Accessibility framework
(AXUIElement APIs), which would violate App Store guideline 2.4.5.

## Clean User Test (from scratch)

Use this sequence to test onboarding exactly as a first-time user:

1. Remove the installed app plus app-specific state:
   - `make reset-fresh-test`
   - `bash scripts/reset-fresh-test.sh`
   - If `/Applications/HoldToTalk.app` is admin-owned: `sudo APP_USER=$USER bash scripts/reset-fresh-test.sh --yes`
   - If the sandbox container under `~/Library/Containers/com.holdtotalk.app` survives with `Operation not permitted`, grant Full Disk Access to your terminal app and rerun
2. Install app into `/Applications`:
   - `make install`
3. Launch from `/Applications/HoldToTalk.app`

## Why `/Applications` Matters

macOS privacy entries are tied to the signed app identity and path context.
Running from random build folders can create confusing permission behavior.
For reliable user-like testing, always launch from `/Applications`.
