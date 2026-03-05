import AppKit
import Foundation

enum AppInstallOutcome {
    case success(destination: URL)
    case failure(message: String)
}

func isInstalledInApplicationsFolder(
    appURL: URL = Bundle.main.bundleURL,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
) -> Bool {
    let installParent = canonicalURL(appURL).deletingLastPathComponent()
    return installBaseDirectories(homeDirectory: homeDirectory).contains {
        canonicalURL($0) == installParent
    }
}

/// Attempts to install the current app bundle into /Applications and relaunch.
/// Falls back to ~/Applications if /Applications is not writable.
@MainActor
func installToApplicationsAndRelaunch(
    appURL: URL = Bundle.main.bundleURL,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
) -> AppInstallOutcome {
    let fileManager = FileManager.default
    let sourceURL = canonicalURL(appURL)
    let appName = sourceURL.lastPathComponent

    let destinations = installBaseDirectories(homeDirectory: homeDirectory)

    // Already installed in one of the supported Application folders.
    for base in destinations {
        let destination = canonicalURL(base.appendingPathComponent(appName, isDirectory: true))
        if sourceURL == destination {
            return .success(destination: destination)
        }
    }

    var lastError: Error?
    for base in destinations {
        let destination = canonicalURL(base.appendingPathComponent(appName, isDirectory: true))
        do {
            try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: sourceURL, to: destination)

            // Only terminate if the new instance actually launches.
            // If open() fails (e.g. Gatekeeper quarantine), stay alive so the user sees an error
            // rather than the app silently disappearing.
            guard NSWorkspace.shared.open(destination) else {
                lastError = NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileWriteNoPermissionError,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Copied to \(destination.path) but could not launch — check Gatekeeper settings."]
                )
                continue
            }
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

func installBaseDirectories(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
) -> [URL] {
    [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        homeDirectory.appendingPathComponent("Applications", isDirectory: true),
    ]
}

private func canonicalURL(_ url: URL) -> URL {
    url.resolvingSymlinksInPath().standardizedFileURL
}
