import Basic
import Foundation
import TuistCore
import XCTest
@testable import SPMUtility
@testable import TuistCoreTesting
@testable import TuistEnvKit

final class InstallCommandTests: XCTestCase {
    var parser: ArgumentParser!
    var versionsController: MockVersionsController!
    var installer: MockInstaller!
    var subject: InstallCommand!

    override func setUp() {
        super.setUp()
        mockEnvironment()

        parser = ArgumentParser(usage: "test", overview: "overview")
        versionsController = try! MockVersionsController()
        installer = MockInstaller()
        subject = InstallCommand(parser: parser,
                                 versionsController: versionsController,
                                 installer: installer)
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

        XCTAssertPrinterOutputContains("Version 3.2.1 already installed, skipping")
    }

    func test_run() throws {
        let result = try parser.parse(["install", "3.2.1"])

        versionsController.versionsStub = []

        var installArgs: [(version: String, force: Bool)] = []
        installer.installStub = { version, force in installArgs.append((version: version, force: force)) }

        try subject.run(with: result)

        XCTAssertEqual(installArgs.count, 1)
        XCTAssertEqual(installArgs.first?.version, "3.2.1")
        XCTAssertEqual(installArgs.first?.force, false)
    }

    func test_run_when_force() throws {
        let result = try parser.parse(["install", "3.2.1", "-f"])

        versionsController.versionsStub = []

        var installArgs: [(version: String, force: Bool)] = []
        installer.installStub = { version, force in installArgs.append((version: version, force: force)) }

        try subject.run(with: result)

        XCTAssertEqual(installArgs.count, 1)
        XCTAssertEqual(installArgs.first?.version, "3.2.1")
        XCTAssertEqual(installArgs.first?.force, true)
    }
}
