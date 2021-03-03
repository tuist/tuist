import Foundation
import TSCBasic
import TuistSupport
import XCTest
@testable import TuistEnvKit
@testable import TuistSupportTesting

final class UninstallServiceTests: TuistUnitTestCase {
    var versionsController: MockVersionsController!
    var installer: MockInstaller!
    var subject: UninstallService!

    override func setUp() {
        super.setUp()
        versionsController = try! MockVersionsController()
        installer = MockInstaller()
        subject = UninstallService(
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

    func test_run_when_version_is_installed() throws {
        versionsController.versionsStub = [InstalledVersion.reference("3.2.1")]
        var uninstalledVersion: String?
        versionsController.uninstallStub = { uninstalledVersion = $0 }

        try subject.run(version: "3.2.1")

        XCTAssertPrinterOutputContains("Version 3.2.1 uninstalled")
        XCTAssertEqual(uninstalledVersion, "3.2.1")
    }

    func test_run_when_version_is_installed_and_throws() throws {
        versionsController.versionsStub = [InstalledVersion.reference("3.2.1")]

        let error = NSError.test()
        versionsController.uninstallStub = { _ in throw error }

        XCTAssertThrowsError(try subject.run(version: "3.2.1")) {
            XCTAssertEqual($0 as NSError, error)
        }
    }

    func test_run_when_version_is_not_installed() throws {
        versionsController.versionsStub = []

        try subject.run(version: "3.2.1")

        XCTAssertPrinterOutputContains("Version 3.2.1 cannot be uninstalled because it's not installed")
    }
}
