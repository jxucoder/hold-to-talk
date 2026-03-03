import AppKit
import Foundation

enum AppInstallOutcome {
    case success(destination: URL)
    case failure(message: String)
}

func isInstalledInApplicationsFolder() -> Bool {
    let appPath = Bundle.main.bundleURL.standardizedFileURL.path
    return appPath.hasPrefix("/Applications/")
}

/// Attempts to install the current app bundle into /Applications and relaunch.
/// Falls back to ~/Applications if /Applications is not writable.
@MainActor
func installToApplicationsAndRelaunch() -> AppInstallOutcome {
    let fileManager = FileManager.default
    let sourceURL = Bundle.main.bundleURL.standardizedFileURL
    let appName = sourceURL.lastPathComponent

    let destinations = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
    ]

    var lastError: Error?
    for base in destinations {
        let destination = base.appendingPathComponent(appName, isDirectory: true)
        do {
            try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: sourceURL, to: destination)

            NSWorkspace.shared.open(destination)
            NSApp.terminate(nil)
            return .success(destination: destination)
        } catch {
            lastError = error
        }
    }

    let detail = lastError?.localizedDescription ?? "unknown error"
    return .failure(
        message: "Could not install automatically (\(detail)). Move HoldToTalk.app to /Applications manually."
    )
}
