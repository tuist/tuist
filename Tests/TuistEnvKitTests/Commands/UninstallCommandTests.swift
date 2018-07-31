import Basic
import Foundation
import TuistCore
@testable import TuistCoreTesting
@testable import TuistEnvKit
@testable import Utility
import XCTest

final class UninstallCommandTests: XCTestCase {
    var parser: ArgumentParser!
    var versionsController: MockVersionsController!
    var installer: MockInstaller!
    var printer: MockPrinter!
    var subject: UninstallCommand!

    override func setUp() {
        super.setUp()
        parser = ArgumentParser(usage: "test", overview: "overview")
        versionsController = try! MockVersionsController()
        installer = MockInstaller()
        printer = MockPrinter()
        subject = UninstallCommand(parser: parser,
                                   versionsController: versionsController,
                                   installer: installer,
                                   printer: printer)
    }

    func test_command() {
        XCTAssertEqual(UninstallCommand.command, "uninstall")
    }

    func test_overview() {
        XCTAssertEqual(UninstallCommand.overview, "Uninstalls a version of tuist")
    }

    func test_init_registers_the_command() {
        XCTAssertEqual(parser.subparsers.count, 1)
        XCTAssertEqual(parser.subparsers.first?.key, UninstallCommand.command)
        XCTAssertEqual(parser.subparsers.first?.value.overview, UninstallCommand.overview)
    }

    func test_run_when_version_is_installed() throws {
        let result = try parser.parse(["uninstall", "3.2.1"])

        versionsController.versionsStub = [InstalledVersion.reference("3.2.1")]
        var uninstalledVersion: String?
        versionsController.uninstallStub = { uninstalledVersion = $0 }

        try subject.run(with: result)

        XCTAssertEqual(printer.printSuccessArgs.first, "Version 3.2.1 uninstalled")
        XCTAssertEqual(uninstalledVersion, "3.2.1")
    }

    func test_run_when_version_is_installed_and_throws() throws {
        let result = try parser.parse(["uninstall", "3.2.1"])

        versionsController.versionsStub = [InstalledVersion.reference("3.2.1")]

        let error = NSError.test()
        versionsController.uninstallStub = { _ in throw error }

        XCTAssertThrowsError(try subject.run(with: result)) {
            XCTAssertEqual($0 as NSError, error)
        }
    }

    func test_run_when_version_is_not_installed() throws {
        let result = try parser.parse(["uninstall", "3.2.1"])

        versionsController.versionsStub = []

        try subject.run(with: result)

        XCTAssertEqual(printer.printWarningArgs.first, "Version 3.2.1 cannot be uninstalled becuase it's not installed")
    }
}
