import Foundation
import struct TSCUtility.Version
import TuistSupport
import XCTest
@testable import TuistEnvKit
@testable import TuistSupportTesting

final class UpdaterTests: TuistUnitTestCase {
    var versionsController: MockVersionsController!
    var installer: MockInstaller!
    var envInstaller: MockEnvInstaller!
    var versionProvider: MockVersionProvider!
    var subject: Updater!

    override func setUp() {
        super.setUp()

        versionsController = try! MockVersionsController()
        installer = MockInstaller()
        envInstaller = MockEnvInstaller()
        versionProvider = MockVersionProvider()
        subject = Updater(
            versionsController: versionsController,
            installer: installer,
            envInstaller: envInstaller,
            versionProvider: versionProvider
        )
    }

    override func tearDown() {
        versionsController = nil
        installer = nil
        envInstaller = nil
        subject = nil
        versionProvider = nil
        super.tearDown()
    }

    func test_update_when_there_are_no_updates() throws {
        versionsController.semverVersionsStub = ["3.2.1"]
        versionProvider.stubbedLatestVersionResult = Version("3.2.1")

        try subject.update()

        XCTAssertPrinterOutputContains("There are no updates available")
    }

    func test_update_when_there_are_updates() throws {
        versionsController.semverVersionsStub = ["3.1.1"]
        versionProvider.stubbedLatestVersionResult = Version("3.2.1")
        var installArgs: [String] = []
        installer.installStub = { version in installArgs.append(version) }
        envInstaller.installStub = { version in installArgs.append(version) }

        try subject.update()

        XCTAssertPrinterOutputContains("Installing new version available 3.2.1")
        XCTAssertEqual(installArgs, ["3.2.1", "3.2.1"])
    }

    func test_update_when_no_local_versions_available() throws {
        versionsController.semverVersionsStub = []
        versionProvider.stubbedLatestVersionResult = Version("3.2.1")

        var installArgs: [String] = []
        installer.installStub = { version in installArgs.append(version) }
        envInstaller.installStub = { version in installArgs.append(version) }

        try subject.update()

        XCTAssertPrinterOutputContains("No local versions available. Installing the latest version 3.2.1")
        XCTAssertEqual(installArgs, ["3.2.1", "3.2.1"])
    }
}
