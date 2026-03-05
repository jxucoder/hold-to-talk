import XCTest
@testable import HoldToTalk

final class AppInstallHelperTests: XCTestCase {
    func testInstallBaseDirectoriesIncludeSystemAndUserApplications() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let bases = installBaseDirectories(homeDirectory: home).map(\.path)
        XCTAssertEqual(bases, ["/Applications", "/Users/tester/Applications"])
    }

    func testIsInstalledInApplicationsFolderAcceptsSystemApplications() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let appURL = URL(fileURLWithPath: "/Applications/HoldToTalk.app", isDirectory: true)
        XCTAssertTrue(isInstalledInApplicationsFolder(appURL: appURL, homeDirectory: home))
    }

    func testIsInstalledInApplicationsFolderAcceptsUserApplications() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let appURL = URL(fileURLWithPath: "/Users/tester/Applications/HoldToTalk.app", isDirectory: true)
        XCTAssertTrue(isInstalledInApplicationsFolder(appURL: appURL, homeDirectory: home))
    }

    func testIsInstalledInApplicationsFolderRejectsOtherLocations() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let appURL = URL(fileURLWithPath: "/Users/tester/Downloads/HoldToTalk.app", isDirectory: true)
        XCTAssertFalse(isInstalledInApplicationsFolder(appURL: appURL, homeDirectory: home))
    }

    func testIsInstalledInApplicationsFolderRejectsNestedSubfolder() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let appURL = URL(fileURLWithPath: "/Applications/Utilities/HoldToTalk.app", isDirectory: true)
        XCTAssertFalse(isInstalledInApplicationsFolder(appURL: appURL, homeDirectory: home))
    }

    func testInstallToApplicationsReturnsSuccessWithoutCopyWhenAlreadyInstalled() async {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let appURL = URL(fileURLWithPath: "/Users/tester/Applications/HoldToTalk.app", isDirectory: true)

        let outcome = await MainActor.run {
            installToApplicationsAndRelaunch(appURL: appURL, homeDirectory: home)
        }

        switch outcome {
        case .success(let destination):
            XCTAssertEqual(destination.path, appURL.path)
        case .failure(let message):
            XCTFail("Expected success, got failure: \(message)")
        }
    }
}
