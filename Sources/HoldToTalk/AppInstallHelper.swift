import AppKit
import Foundation

enum AppInstallOutcome {
    case success(destination: URL)
    case failure(message: String)
}

@MainActor
private func terminateCurrentApp() {
    NSApp.terminate(nil)
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
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    installDirectories: [URL]? = nil,
    fileManager: FileManager = .default,
    workspaceOpen: (URL) -> Bool = { NSWorkspace.shared.open($0) },
    terminate: @MainActor () -> Void = terminateCurrentApp
) -> AppInstallOutcome {
    let sourceURL = canonicalURL(appURL)
    let appName = sourceURL.lastPathComponent

    let destinations = installDirectories ?? installBaseDirectories(homeDirectory: homeDirectory)

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
        let stagingURL = base.appendingPathComponent(".\(appName).\(UUID().uuidString).tmp", isDirectory: true)
        do {
            try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
            try fileManager.copyItem(at: sourceURL, to: stagingURL)

            let installedURL: URL
            if fileManager.fileExists(atPath: destination.path) {
                let replacedURL = try fileManager.replaceItemAt(
                    destination,
                    withItemAt: stagingURL,
                    backupItemName: nil,
                    options: []
                )
                installedURL = canonicalURL(replacedURL ?? destination)
            } else {
                try fileManager.moveItem(at: stagingURL, to: destination)
                installedURL = destination
            }

            // Only terminate if the new instance actually launches.
            // If open() fails (e.g. Gatekeeper quarantine), stay alive so the user sees an error
            // rather than the app silently disappearing.
            guard workspaceOpen(installedURL) else {
                lastError = NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileWriteNoPermissionError,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Copied to \(installedURL.path) but could not launch — check Gatekeeper settings."]
                )
                continue
            }
            terminate()
            return .success(destination: installedURL)
        } catch {
            lastError = error
            if fileManager.fileExists(atPath: stagingURL.path) {
                try? fileManager.removeItem(at: stagingURL)
            }
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
