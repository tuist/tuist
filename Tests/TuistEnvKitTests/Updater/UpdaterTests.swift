import Foundation
import struct TSCUtility.Version
import TuistSupport
import XCTest
@testable import TuistEnvKit
@testable import TuistSupportTesting

final class UpdaterTests: TuistUnitTestCase {
    var versionsController: MockVersionsController!
    var installer: MockInstaller!
    var envUpdater: MockEnvUpdater!
    var googleCloudStorageClient: MockGoogleCloudStorageClient!
    var subject: Updater!

    override func setUp() {
        super.setUp()

        versionsController = try! MockVersionsController()
        installer = MockInstaller()
        envUpdater = MockEnvUpdater()
        googleCloudStorageClient = MockGoogleCloudStorageClient()
        subject = Updater(
            versionsController: versionsController,
            installer: installer,
            envUpdater: envUpdater,
            googleCloudStorageClient: googleCloudStorageClient
        )
    }

    override func tearDown() {
        super.tearDown()

        versionsController = nil
        installer = nil
        envUpdater = nil
        subject = nil
        googleCloudStorageClient = nil
    }

    func test_update_when_there_are_no_updates() throws {
        versionsController.semverVersionsStub = ["3.2.1"]
        googleCloudStorageClient.latestVersionStub = Version(string: "3.2.1")!

        try subject.update()

        XCTAssertPrinterOutputContains("There are no updates available")
        XCTAssertEqual(envUpdater.updateCallCount, 1)
    }

    func test_update_when_there_are_updates() throws {
        versionsController.semverVersionsStub = ["3.1.1"]
        googleCloudStorageClient.latestVersionStub = Version(string: "3.2.1")!
        var installArgs: [String] = []
        installer.installStub = { version in installArgs.append(version) }

        try subject.update()

        XCTAssertPrinterOutputContains("Installing new version available 3.2.1")
        XCTAssertEqual(installArgs.count, 1)
        XCTAssertEqual(installArgs.first, "3.2.1")
        XCTAssertEqual(envUpdater.updateCallCount, 1)
    }

    func test_update_when_no_local_versions_available() throws {
        versionsController.semverVersionsStub = []
        googleCloudStorageClient.latestVersionStub = Version(string: "3.2.1")!
        var installArgs: [String] = []
        installer.installStub = { version in installArgs.append(version) }

        try subject.update()

        XCTAssertPrinterOutputContains("No local versions available. Installing the latest version 3.2.1")
        XCTAssertEqual(installArgs.count, 1)
        XCTAssertEqual(installArgs.first, "3.2.1")
        XCTAssertEqual(envUpdater.updateCallCount, 1)
    }
}
