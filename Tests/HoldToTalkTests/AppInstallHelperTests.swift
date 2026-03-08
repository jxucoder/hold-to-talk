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

    @MainActor
    func testInstallToApplicationsReturnsSuccessWithoutCopyWhenAlreadyInstalled() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let appURL = URL(fileURLWithPath: "/Users/tester/Applications/HoldToTalk.app", isDirectory: true)

        let outcome = installToApplicationsAndRelaunch(appURL: appURL, homeDirectory: home)

        switch outcome {
        case .success(let destination):
            XCTAssertEqual(destination.path, appURL.path)
        case .failure(let message):
            XCTFail("Expected success, got failure: \(message)")
        }
    }

    @MainActor
    func testInstallToApplicationsCopiesAppAndLaunchesReplacement() throws {
        let fileManager = FileManager.default
        let root = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }

        let home = root.appendingPathComponent("Home", isDirectory: true)
        let downloads = root.appendingPathComponent("Downloads", isDirectory: true)
        let applications = home.appendingPathComponent("Applications", isDirectory: true)
        let sourceApp = downloads.appendingPathComponent("HoldToTalk.app", isDirectory: true)
        let expectedDestination = applications.appendingPathComponent("HoldToTalk.app", isDirectory: true)
        try createFakeApp(at: sourceApp, marker: "fresh build")

        var launchedURL: URL?
        var didTerminate = false

        let outcome = installToApplicationsAndRelaunch(
            appURL: sourceApp,
            homeDirectory: home,
            installDirectories: [applications],
            fileManager: fileManager,
            workspaceOpen: { url in
                launchedURL = url
                return true
            },
            terminate: {
                didTerminate = true
            }
        )

        switch outcome {
        case .success(let destination):
            XCTAssertEqual(destination.path, expectedDestination.path)
            XCTAssertEqual(launchedURL?.path, expectedDestination.path)
            XCTAssertTrue(didTerminate)
            XCTAssertEqual(try markerValue(at: expectedDestination), "fresh build")
        case .failure(let message):
            XCTFail("Expected success, got failure: \(message)")
        }
    }

    @MainActor
    func testInstallToApplicationsReplacesExistingAppWithoutDeletingFirst() throws {
        let fileManager = FileManager.default
        let root = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }

        let home = root.appendingPathComponent("Home", isDirectory: true)
        let applications = home.appendingPathComponent("Applications", isDirectory: true)
        let downloads = root.appendingPathComponent("Downloads", isDirectory: true)
        let sourceApp = downloads.appendingPathComponent("HoldToTalk.app", isDirectory: true)
        let destinationApp = applications.appendingPathComponent("HoldToTalk.app", isDirectory: true)
        try createFakeApp(at: sourceApp, marker: "new build")
        try createFakeApp(at: destinationApp, marker: "old build")

        let outcome = installToApplicationsAndRelaunch(
            appURL: sourceApp,
            homeDirectory: home,
            installDirectories: [applications],
            fileManager: fileManager,
            workspaceOpen: { _ in true },
            terminate: {}
        )

        switch outcome {
        case .success(let destination):
            XCTAssertEqual(destination.path, destinationApp.path)
            XCTAssertEqual(try markerValue(at: destinationApp), "new build")
        case .failure(let message):
            XCTFail("Expected success, got failure: \(message)")
        }
    }

    @MainActor
    func testInstallToApplicationsPreservesExistingAppWhenCopyFails() throws {
        let fileManager = FileManager.default
        let root = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }

        let home = root.appendingPathComponent("Home", isDirectory: true)
        let applications = home.appendingPathComponent("Applications", isDirectory: true)
        let missingSource = root.appendingPathComponent("Downloads/HoldToTalk.app", isDirectory: true)
        let destinationApp = applications.appendingPathComponent("HoldToTalk.app", isDirectory: true)
        try createFakeApp(at: destinationApp, marker: "existing install")

        let outcome = installToApplicationsAndRelaunch(
            appURL: missingSource,
            homeDirectory: home,
            installDirectories: [applications],
            fileManager: fileManager,
            workspaceOpen: { _ in true },
            terminate: {}
        )

        switch outcome {
        case .success(let destination):
            XCTFail("Expected failure, got success at \(destination.path)")
        case .failure:
            XCTAssertEqual(try markerValue(at: destinationApp), "existing install")
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let fileManager = FileManager.default
        let url = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func createFakeApp(at appURL: URL, marker: String) throws {
        let fileManager = FileManager.default
        let executableDirectory = appURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try fileManager.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
        try marker.write(
            to: executableDirectory.appendingPathComponent("HoldToTalk"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func markerValue(at appURL: URL) throws -> String {
        try String(
            contentsOf: appURL.appendingPathComponent("Contents/MacOS/HoldToTalk"),
            encoding: .utf8
        )
    }
}
