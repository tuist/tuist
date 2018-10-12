import Basic
import Foundation
@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistEnvKit
@testable import Utility
import XCTest

final class BundleCommandErrorTests: XCTestCase {
    func test_type() {
        let path = AbsolutePath("/test")
        XCTAssertEqual(BundleCommandError.missingVersionFile(path).type, .abort)
    }

    func test_description() {
        let path = AbsolutePath("/test")
        XCTAssertEqual(BundleCommandError.missingVersionFile(path).description, "Couldn't find a .tuist-version file in the directory \(path.asString)")
    }
}

final class BundleCommandTests: XCTestCase {
    var parser: ArgumentParser!
    var versionsController: MockVersionsController!
    var fileHandler: MockFileHandler!
    var printer: MockPrinter!
    var installer: MockInstaller!
    var subject: BundleCommand!
    var tmpDir: TemporaryDirectory!

    override func setUp() {
        super.setUp()
        parser = ArgumentParser(usage: "test", overview: "overview")
        versionsController = try! MockVersionsController()
        fileHandler = try! MockFileHandler()
        printer = MockPrinter()
        installer = MockInstaller()
        tmpDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
        subject = BundleCommand(parser: parser,
                                versionsController: versionsController,
                                fileHandler: fileHandler,
                                printer: printer,
                                installer: installer)
    }

    func test_init_registers_the_command() {
        XCTAssertEqual(parser.subparsers.count, 1)
        XCTAssertEqual(parser.subparsers.first?.key, BundleCommand.command)
        XCTAssertEqual(parser.subparsers.first?.value.overview, BundleCommand.overview)
    }

    func test_command() {
        XCTAssertEqual(BundleCommand.command, "bundle")
    }

    func test_overview() {
        XCTAssertEqual(BundleCommand.overview, "Bundles the version specified in the .tuist-version file into the .tuist-bin directory")
    }

    func test_run_throws_when_there_is_no_xmp_version_in_the_directory() throws {
        let result = try parser.parse([])
        XCTAssertThrowsError(try subject.run(with: result)) {
            XCTAssertEqual($0 as? BundleCommandError, BundleCommandError.missingVersionFile(fileHandler.currentPath))
        }
    }

    func test_run_installs_the_app_if_it_doesnt_exist() throws {
        let result = try parser.parse([])
        let tuistVersionPath = fileHandler.currentPath.appending(component: Constants.versionFileName)
        try "3.2.1".write(to: tuistVersionPath.url, atomically: true, encoding: .utf8)

        installer.installStub = { versionToInstall in
            let versionPath = self.versionsController.path(version: versionToInstall)
            try self.fileHandler.createFolder(versionPath)
            try Data().write(to: versionPath.appending(component: "test").url)
        }

        try subject.run(with: result)

        let bundledTestFilePath = fileHandler.currentPath
            .appending(component: Constants.binFolderName)
            .appending(component: "test")

        XCTAssertTrue(fileHandler.exists(bundledTestFilePath))
    }

    func test_run_doesnt_install_the_app_if_it_already_exists() throws {
        let result = try parser.parse([])
        let tuistVersionPath = fileHandler.currentPath.appending(component: Constants.versionFileName)
        try "3.2.1".write(to: tuistVersionPath.url, atomically: true, encoding: .utf8)
        let versionPath = versionsController.path(version: "3.2.1")
        try fileHandler.createFolder(versionPath)

        try subject.run(with: result)

        XCTAssertEqual(installer.installCallCount, 0)
    }

    func test_run_prints_the_right_messages() throws {
        let result = try parser.parse([])
        let tuistVersionPath = fileHandler.currentPath.appending(component: Constants.versionFileName)
        let binPath = fileHandler.currentPath.appending(component: Constants.binFolderName)

        try "3.2.1".write(to: tuistVersionPath.url, atomically: true, encoding: .utf8)

        installer.installStub = { versionToInstall in
            let versionPath = self.versionsController.path(version: versionToInstall)
            try self.fileHandler.createFolder(versionPath)
            try Data().write(to: versionPath.appending(component: "test").url)
        }

        try subject.run(with: result)

        XCTAssertEqual(printer.printSectionArgs.count, 1)
        XCTAssertEqual(printer.printSectionArgs.first, "Bundling the version 3.2.1 in the directory \(binPath.asString)")

        XCTAssertEqual(printer.printArgs.count, 1)
        XCTAssertEqual(printer.printArgs.first, "Version 3.2.1 not available locally. Installing...")

        XCTAssertEqual(printer.printSuccessArgs.count, 1)
        XCTAssertEqual(printer.printSuccessArgs.first, "tuist bundled successfully at \(binPath.asString)")
    }
}
