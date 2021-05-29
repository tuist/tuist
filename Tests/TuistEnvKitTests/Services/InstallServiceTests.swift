import Foundation
import TSCBasic
import TuistSupport
import XCTest
@testable import TuistEnvKit
@testable import TuistSupportTesting

final class InstallServiceTests: TuistUnitTestCase {
    var versionsController: MockVersionsController!
    var installer: MockInstaller!
    var subject: InstallService!

    override func setUp() {
        super.setUp()

        versionsController = try! MockVersionsController()
        installer = MockInstaller()
        subject = InstallService(
            versionsController: versionsController,
            installer: installer
        )
    }

    override func tearDown() {
        versionsController = nil
        installer = nil
        subject = nil

        super.tearDown()
    }

    func test_run_when_version_is_already_installed() throws {
        versionsController.versionsStub = [InstalledVersion.reference("3.2.1")]

        try subject.run(version: "3.2.1")

        XCTAssertPrinterOutputContains("Version 3.2.1 already installed, skipping")
    }

    func test_run() throws {
        versionsController.versionsStub = []

        var installArgs: [String] = []
        installer.installStub = { version in installArgs.append(version) }

        try subject.run(version: "3.2.1")

        XCTAssertEqual(installArgs.count, 1)
        XCTAssertEqual(installArgs.first, "3.2.1")
    }

    func test_run_when_force() throws {
        versionsController.versionsStub = []

        var installArgs: [String] = []
        installer.installStub = { version in installArgs.append(version) }

        try subject.run(version: "3.2.1")

        XCTAssertEqual(installArgs.count, 1)
        XCTAssertEqual(installArgs.first, "3.2.1")
    }
}
