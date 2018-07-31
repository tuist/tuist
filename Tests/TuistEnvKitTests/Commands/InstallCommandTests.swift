import Basic
import Foundation
import TuistCore
@testable import TuistCoreTesting
@testable import TuistEnvKit
@testable import Utility
import XCTest

final class InstallCommandTests: XCTestCase {
    var parser: ArgumentParser!
    var versionsController: MockVersionsController!
    var installer: MockInstaller!
    var printer: MockPrinter!
    var subject: InstallCommand!

    override func setUp() {
        super.setUp()
        parser = ArgumentParser(usage: "test", overview: "overview")
        versionsController = try! MockVersionsController()
        installer = MockInstaller()
        printer = MockPrinter()
        subject = InstallCommand(parser: parser,
                                 versionsController: versionsController,
                                 installer: installer,
                                 printer: printer)
    }

    func test_command() {
        XCTAssertEqual(InstallCommand.command, "install")
    }

    func test_overview() {
        XCTAssertEqual(InstallCommand.overview, "Installs a version of tuist")
    }

    func test_init_registers_the_command() {
        XCTAssertEqual(parser.subparsers.count, 1)
        XCTAssertEqual(parser.subparsers.first?.key, InstallCommand.command)
        XCTAssertEqual(parser.subparsers.first?.value.overview, InstallCommand.overview)
    }

    func test_run_when_version_is_already_installed() throws {
        let result = try parser.parse(["install", "3.2.1"])

        versionsController.versionsStub = [InstalledVersion.reference("3.2.1")]

        try subject.run(with: result)

        XCTAssertEqual(printer.printWarningArgs.first, "Version 3.2.1 already installed, skipping")
    }

    func test_run() throws {
        let result = try parser.parse(["install", "3.2.1"])

        versionsController.versionsStub = []

        var installedVersion: String?
        installer.installStub = { installedVersion = $0 }

        try subject.run(with: result)

        XCTAssertEqual(installedVersion, "3.2.1")
    }
}
