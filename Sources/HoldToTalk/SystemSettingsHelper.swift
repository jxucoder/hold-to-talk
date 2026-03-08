import AppKit
import ApplicationServices
import Foundation

let accessibilityPromptedDefaultsKey = "hasPromptedAccessibility"
let inputMonitoringPromptedDefaultsKey = "hasPromptedInputMonitoring"

enum PermissionRequestResult {
    case granted
    case prompted
    case openedSettings
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
func requestAccessibilityAccess() -> PermissionRequestResult {
    if AXIsProcessTrusted() {
        return .granted
    }

    let defaults = UserDefaults.standard
    if defaults.bool(forKey: accessibilityPromptedDefaultsKey) {
        openSystemSettings("Privacy_Accessibility")
        return .openedSettings
    }

    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    let trusted = AXIsProcessTrustedWithOptions(options)
    defaults.set(true, forKey: accessibilityPromptedDefaultsKey)
    return trusted ? .granted : .prompted
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
