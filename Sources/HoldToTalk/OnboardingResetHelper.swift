import Foundation

let onboardingCompleteDefaultsKey = "onboardingComplete"
let onboardingStepDefaultsKey = "onboardingStep"
let dismissedInstallPromptDefaultsKey = "dismissedInstallPrompt"
let whisperModelDefaultsKey = "whisperModel"
let transcriptionProfileDefaultsKey = "transcriptionProfile"
let cleanupEnabledDefaultsKey = "cleanupEnabled"
let cleanupPromptDefaultsKey = "cleanupPrompt"
let hotkeyChoiceDefaultsKey = "hotkeyChoice"
let diagnosticLoggingEnabledDefaultsKey = "diagnosticLoggingEnabled"

func shouldResetAppStateForFreshOnboarding(defaults: UserDefaults = .standard) -> Bool {
    #if DEBUG
    if DebugFlags.resetOnboarding {
        return true
    }
    #endif
    return !defaults.bool(forKey: onboardingCompleteDefaultsKey)
}

func holdToTalkApplicationSupportDirectory(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
) -> URL {
    homeDirectory
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("HoldToTalk", isDirectory: true)
}

func holdToTalkCacheDirectories(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.holdtotalk.app"
) -> [URL] {
    let cachesRoot = homeDirectory
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Caches", isDirectory: true)

    return [
        cachesRoot.appendingPathComponent("HoldToTalk", isDirectory: true),
        cachesRoot.appendingPathComponent(bundleIdentifier, isDirectory: true),
    ]
}

func resetPersistedAppStateForFreshOnboarding(
    defaults: UserDefaults = .standard,
    bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.holdtotalk.app",
    fileManager: FileManager = .default,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
) {
    defaults.removePersistentDomain(forName: bundleIdentifier)
    defaults.synchronize()

    let appSupportDirectory = holdToTalkApplicationSupportDirectory(homeDirectory: homeDirectory)
    if fileManager.fileExists(atPath: appSupportDirectory.path) {
        if let contents = try? fileManager.contentsOfDirectory(
            at: appSupportDirectory,
            includingPropertiesForKeys: nil
        ) {
            for child in contents {
                try? fileManager.removeItem(at: child)
            }
        } else {
            try? fileManager.removeItem(at: appSupportDirectory)
        }
    }

    try? fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)

    for cacheDirectory in holdToTalkCacheDirectories(
        homeDirectory: homeDirectory,
        bundleIdentifier: bundleIdentifier
    ) {
        guard fileManager.fileExists(atPath: cacheDirectory.path) else { continue }
        try? fileManager.removeItem(at: cacheDirectory)
    }
}
