import XCTest
@testable import HoldToTalk

final class HoldToTalkAppTests: XCTestCase {
    func testShouldShowLaunchInstallPromptWhenNotInstalledAndNotOnboarding() {
        XCTAssertTrue(
            shouldShowLaunchInstallPrompt(
                installedInApplications: false,
                installPromptDismissed: false,
                openingInitialOnboarding: false
            )
        )
    }

    func testShouldNotShowLaunchInstallPromptWhenOpeningOnboarding() {
        XCTAssertFalse(
            shouldShowLaunchInstallPrompt(
                installedInApplications: false,
                installPromptDismissed: false,
                openingInitialOnboarding: true
            )
        )
    }

    func testShouldNotShowLaunchInstallPromptWhenAlreadyInstalled() {
        XCTAssertFalse(
            shouldShowLaunchInstallPrompt(
                installedInApplications: true,
                installPromptDismissed: false,
                openingInitialOnboarding: false
            )
        )
    }

    func testShouldNotShowLaunchInstallPromptWhenUserDismissedIt() {
        XCTAssertFalse(
            shouldShowLaunchInstallPrompt(
                installedInApplications: false,
                installPromptDismissed: true,
                openingInitialOnboarding: false
            )
        )
    }
}
