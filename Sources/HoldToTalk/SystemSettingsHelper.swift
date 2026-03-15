import AppKit
import CoreGraphics
import Foundation

let postEventPromptedDefaultsKey = "hasPromptedPostEvent"
let inputMonitoringPromptedDefaultsKey = "hasPromptedInputMonitoring"

enum PermissionRequestResult {
    case granted
    case prompted
    case openedSettings
}

/// Checks whether PostEvent access is granted.
///
/// `CGPreflightPostEventAccess()` is known to cache its result for the lifetime of the
/// process. Once it returns `false`, it may keep returning `false` even after the user
/// grants permission in System Settings. The only fully reliable fix is to relaunch.
/// As a best-effort heuristic, we also attempt a test CGEvent post — if the system
/// silently accepts it, the permission is granted even though preflight still says no.
func checkPostEventAccess() -> Bool {
    if CGPreflightPostEventAccess() { return true }
    // Best-effort: try posting a no-visible-effect event (mouse-move to current position).
    // If PostEvent is granted, the post succeeds silently. If not, it's silently dropped.
    // We check preflight again after the post in case it refreshes the cache.
    guard let event = CGEvent(source: nil) else { return false }
    event.type = .mouseMoved
    event.post(tap: .cghidEventTap)
    return CGPreflightPostEventAccess()
}

/// Relaunches the app. Used when PostEvent permission is granted in System Settings
/// but `CGPreflightPostEventAccess()` still returns a stale `false`.
func relaunchApp() {
    let url = Bundle.main.bundleURL
    let config = NSWorkspace.OpenConfiguration()
    config.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
}

/// Opens the specified System Settings / System Preferences privacy pane.
///
/// Tries the legacy `com.apple.preference.security` URL first, then the
/// macOS 15+ `com.apple.settings.PrivacySecurity.extension` variant, and
/// falls back to the top-level Security & Privacy pane.
func openSystemSettings(_ anchor: String) {
    let urls = [
        "x-apple.systempreferences:com.apple.preference.security?\(anchor)",
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)",
    ]
    for str in urls {
        if let url = URL(string: str), NSWorkspace.shared.open(url) {
            return
        }
    }
    if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
        NSWorkspace.shared.open(fallback)
    }
}

@discardableResult
func requestPostEventAccess() -> PermissionRequestResult {
    if checkPostEventAccess() {
        return .granted
    }

    let defaults = UserDefaults.standard
    if defaults.bool(forKey: postEventPromptedDefaultsKey) {
        openSystemSettings("Privacy_Accessibility")
        return .openedSettings
    }

    let granted = CGRequestPostEventAccess()
    defaults.set(true, forKey: postEventPromptedDefaultsKey)
    return (granted || checkPostEventAccess()) ? .granted : .prompted
}

@discardableResult
func requestInputMonitoringAccess() -> PermissionRequestResult {
    if CGPreflightListenEventAccess() {
        return .granted
    }

    let defaults = UserDefaults.standard
    if defaults.bool(forKey: inputMonitoringPromptedDefaultsKey) {
        openSystemSettings("Privacy_ListenEvent")
        return .openedSettings
    }

    let granted = CGRequestListenEventAccess()
    defaults.set(true, forKey: inputMonitoringPromptedDefaultsKey)
    return (granted || CGPreflightListenEventAccess()) ? .granted : .prompted
}
