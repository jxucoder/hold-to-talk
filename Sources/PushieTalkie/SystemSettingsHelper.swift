import AppKit

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
