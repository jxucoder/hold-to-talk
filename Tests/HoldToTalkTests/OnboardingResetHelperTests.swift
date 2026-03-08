import XCTest
@testable import HoldToTalk

final class OnboardingResetHelperTests: XCTestCase {
    func testShouldResetAppStateForFreshOnboardingWhenOnboardingIncomplete() {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }

        defaults.set(false, forKey: onboardingCompleteDefaultsKey)

        XCTAssertTrue(shouldResetAppStateForFreshOnboarding(defaults: defaults))
    }

    func testShouldNotResetAppStateForFreshOnboardingWhenOnboardingComplete() {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }

        defaults.set(true, forKey: onboardingCompleteDefaultsKey)

        XCTAssertFalse(shouldResetAppStateForFreshOnboarding(defaults: defaults))
    }

    func testResetPersistedAppStateClearsDefaultsAndAppDataButKeepsAppSupportRoot() throws {
        let fileManager = FileManager.default
        let root = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }

        let home = root.appendingPathComponent("Home", isDirectory: true)
        let suiteName = #function
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: onboardingCompleteDefaultsKey)
        defaults.set(3, forKey: onboardingStepDefaultsKey)
        defaults.set("base", forKey: whisperModelDefaultsKey)
        defaults.set("custom", forKey: cleanupPromptDefaultsKey)

        let appSupport = holdToTalkApplicationSupportDirectory(homeDirectory: home)
        let appSupportChild = appSupport.appendingPathComponent("models/cache.bin")
        let logFile = appSupport.appendingPathComponent("debug.log")
        let unrelatedLibraryFile = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Preferences", isDirectory: true)
            .appendingPathComponent("keep.txt")

        let cacheDirectories = holdToTalkCacheDirectories(
            homeDirectory: home,
            bundleIdentifier: suiteName
        )

        try fileManager.createDirectory(
            at: appSupportChild.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "model".write(to: appSupportChild, atomically: true, encoding: .utf8)
        try "log".write(to: logFile, atomically: true, encoding: .utf8)
        try fileManager.createDirectory(
            at: unrelatedLibraryFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "keep".write(to: unrelatedLibraryFile, atomically: true, encoding: .utf8)

        for cacheDirectory in cacheDirectories {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try "cache".write(
                to: cacheDirectory.appendingPathComponent("artifact.txt"),
                atomically: true,
                encoding: .utf8
            )
        }

        resetPersistedAppStateForFreshOnboarding(
            defaults: defaults,
            bundleIdentifier: suiteName,
            fileManager: fileManager,
            homeDirectory: home
        )

        XCTAssertFalse(defaults.bool(forKey: onboardingCompleteDefaultsKey))
        XCTAssertNil(defaults.object(forKey: onboardingStepDefaultsKey))
        XCTAssertNil(defaults.object(forKey: whisperModelDefaultsKey))
        XCTAssertNil(defaults.object(forKey: cleanupPromptDefaultsKey))

        XCTAssertTrue(fileManager.fileExists(atPath: appSupport.path))
        let appSupportContents = try fileManager.contentsOfDirectory(
            at: appSupport,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(appSupportContents.isEmpty)

        for cacheDirectory in cacheDirectories {
            XCTAssertFalse(fileManager.fileExists(atPath: cacheDirectory.path))
        }

        XCTAssertTrue(fileManager.fileExists(atPath: unrelatedLibraryFile.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let fileManager = FileManager.default
        let url = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
