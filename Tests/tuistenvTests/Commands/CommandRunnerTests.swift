import Basic
import Foundation
import SPMUtility
import TuistCore
import XCTest
@testable import TuistCoreTesting
@testable import tuistenv

final class CommandRunnerErrorTests: XCTestCase {
    func test_type() {
        XCTAssertEqual(CommandRunnerError.versionNotFound.type, .abort)
    }

    func test_description() {
        XCTAssertEqual(CommandRunnerError.versionNotFound.description, "No valid version has been found locally")
    }
}

final class CommandRunnerTests: XCTestCase {
    var versionResolver: MockVersionResolver!
    var fileHandler: MockFileHandler!
    var printer: MockPrinter!
    var system: MockSystem!
    var updater: MockUpdater!
    var versionsController: MockVersionsController!
    var installer: MockInstaller!
    var arguments: [String] = []
    var exited: Int?
    var subject: CommandRunner!

    override func setUp() {
        super.setUp()
        versionResolver = MockVersionResolver()
        fileHandler = try! MockFileHandler()
        printer = MockPrinter()
        system = MockSystem()
        updater = MockUpdater()
        versionsController = try! MockVersionsController()
        installer = MockInstaller()
        subject = CommandRunner(versionResolver: versionResolver,
                                fileHandler: fileHandler,
                                printer: printer,
                                system: system,
                                updater: updater,
                                installer: installer,
                                versionsController: versionsController,
                                arguments: { self.arguments },
                                exiter: { self.exited = $0 })
    }

    func test_when_binary() throws {
        let binaryPath = fileHandler.currentPath.appending(component: "tuist")
        arguments = ["tuist", "--help"]

        versionResolver.resolveStub = { _ in ResolvedVersion.bin(self.fileHandler.currentPath) }
        system.succeedCommand(binaryPath.pathString, "--help", output: "output")
        try subject.run()
    }

    func test_when_binary_and_throws() throws {
        let binaryPath = fileHandler.currentPath.appending(component: "tuist")
        arguments = ["tuist", "--help"]

        versionResolver.resolveStub = { _ in ResolvedVersion.bin(self.fileHandler.currentPath) }
        system.errorCommand(binaryPath.pathString, "--help", error: "error")

        XCTAssertThrowsError(try subject.run())
    }

    func test_when_version_file() throws {
        let binaryPath = fileHandler.currentPath.appending(component: "tuist")
        arguments = ["tuist", "--help"]

        versionsController.versionsStub = []
        versionsController.pathStub = {
            $0 == "3.2.1" ? self.fileHandler.currentPath : AbsolutePath("/invalid")
        }

        versionResolver.resolveStub = { _ in ResolvedVersion.versionFile(self.fileHandler.currentPath, "3.2.1") }

        var installArgs: [(version: String, force: Bool)] = []
        installer.installStub = { version, force in installArgs.append((version: version, force: force)) }
        system.succeedCommand(binaryPath.pathString, "--help", output: "")

        try subject.run()

        XCTAssertEqual(printer.printArgs.count, 2)
        XCTAssertEqual(printer.printArgs.first, "Using version 3.2.1 defined at \(fileHandler.currentPath.pathString)")
        XCTAssertEqual(printer.printArgs.last, "Version 3.2.1 not found locally. Installing...")
        XCTAssertEqual(installArgs.count, 1)
        XCTAssertEqual(installArgs.first?.version, "3.2.1")
    }

    func test_when_version_file_and_install_fails() throws {
        versionsController.versionsStub = []

        versionResolver.resolveStub = { _ in ResolvedVersion.versionFile(self.fileHandler.currentPath, "3.2.1") }

        let error = NSError.test()
        installer.installStub = { _, _ in throw error }

        XCTAssertThrowsError(try subject.run()) {
            XCTAssertEqual($0 as NSError, error)
        }
    }

    func test_when_version_file_and_command_fails() throws {
        let binaryPath = fileHandler.currentPath.appending(component: "tuist")
        arguments = ["tuist", "--help"]

        versionsController.versionsStub = []
        versionsController.pathStub = {
            $0 == "3.2.1" ? self.fileHandler.currentPath : AbsolutePath("/invalid")
        }

        versionResolver.resolveStub = { _ in ResolvedVersion.versionFile(self.fileHandler.currentPath, "3.2.1")
        }

        system.errorCommand(binaryPath.pathString, "--help", error: "error")

        XCTAssertThrowsError(try subject.run())
    }

    func test_when_highest_local_version_and_version_exists() throws {
        let binaryPath = fileHandler.currentPath.appending(component: "tuist")
        arguments = ["tuist", "--help"]

        versionResolver.resolveStub = { _ in ResolvedVersion.undefined }

        versionsController.semverVersionsStub = [Version(string: "3.2.1")!]
        versionsController.pathStub = {
            $0 == "3.2.1" ? self.fileHandler.currentPath : AbsolutePath("/invalid")
        }

        system.succeedCommand(binaryPath.pathString, "--help", output: "")

        try subject.run()
    }

    func test_when_highest_local_version_and_no_local_version() throws {
        let binaryPath = fileHandler.currentPath.appending(component: "tuist")
        arguments = ["tuist", "--help"]

        versionResolver.resolveStub = { _ in ResolvedVersion.undefined }

        versionsController.semverVersionsStub = []
        updater.updateStub = { _ in
            self.versionsController.semverVersionsStub = [Version(string: "3.2.1")!]
        }

        versionsController.pathStub = {
            $0 == "3.2.1" ? self.fileHandler.currentPath : AbsolutePath("/invalid")
        }

        system.succeedCommand(binaryPath.pathString, "--help", output: "")

        try subject.run()
    }

    func test_when_highest_local_version_and_no_local_version_and_update_fails() throws {
        arguments = ["tuist", "--help"]

        versionResolver.resolveStub = { _ in ResolvedVersion.undefined }

        versionsController.semverVersionsStub = []
        let error = NSError.test()
        updater.updateStub = { _ in
            throw error
        }

        XCTAssertThrowsError(try subject.run()) {
            XCTAssertEqual($0 as NSError, error)
        }
    }

    // TODO: And update fails

    func test_when_highest_local_version_and_command_fails() throws {
        let binaryPath = fileHandler.currentPath.appending(component: "tuist")
        arguments = ["tuist", "--help"]

        versionResolver.resolveStub = { _ in ResolvedVersion.undefined }

        versionsController.semverVersionsStub = [Version(string: "3.2.1")!]
        versionsController.pathStub = {
            $0 == "3.2.1" ? self.fileHandler.currentPath : AbsolutePath("/invalid")
        }

        system.errorCommand(binaryPath.pathString, "--help", error: "error")

        XCTAssertThrowsError(try subject.run())
    }
}
