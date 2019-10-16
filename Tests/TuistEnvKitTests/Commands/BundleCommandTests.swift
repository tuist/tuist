import Basic
import Foundation
import XCTest
@testable import SPMUtility
@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistEnvKit

final class BundleCommandErrorTests: XCTestCase {
    func test_type() {
        let path = AbsolutePath("/test")
        XCTAssertEqual(BundleCommandError.missingVersionFile(path).type, .abort)
    }

    func test_description() {
        let path = AbsolutePath("/test")
        XCTAssertEqual(BundleCommandError.missingVersionFile(path).description, "Couldn't find a .tuist-version file in the directory \(path.pathString)")
    }
}

final class BundleCommandTests: TuistUnitTestCase {
    var parser: ArgumentParser!
    var versionsController: MockVersionsController!
    var installer: MockInstaller!
    var subject: BundleCommand!
    var tmpDir: TemporaryDirectory!

    override func setUp() {
        super.setUp()
        parser = ArgumentParser(usage: "test", overview: "overview")
        versionsController = try! MockVersionsController()
        installer = MockInstaller()
        tmpDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
        subject = BundleCommand(parser: parser,
                                versionsController: versionsController,
                                installer: installer)
    }

    override func tearDown() {
        parser = nil
        versionsController = nil
        installer = nil
        subject = nil
        tmpDir = nil
        super.tearDown()
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
        let temporaryPath = try self.temporaryPath()
        let result = try parser.parse([])
        XCTAssertThrowsSpecific(try subject.run(with: result), BundleCommandError.missingVersionFile(temporaryPath))
    }

    func test_run_installs_the_app_if_it_doesnt_exist() throws {
        let temporaryPath = try self.temporaryPath()
        let result = try parser.parse([])
        let tuistVersionPath = temporaryPath.appending(component: Constants.versionFileName)
        try "3.2.1".write(to: tuistVersionPath.url, atomically: true, encoding: .utf8)

        installer.installStub = { version, _ in
            let versionPath = self.versionsController.path(version: version)
            try FileHandler.shared.createFolder(versionPath)
            try Data().write(to: versionPath.appending(component: "test").url)
        }

        try subject.run(with: result)

        let bundledTestFilePath = temporaryPath
            .appending(component: Constants.binFolderName)
            .appending(component: "test")

        XCTAssertTrue(FileHandler.shared.exists(bundledTestFilePath))
    }

    func test_run_doesnt_install_the_app_if_it_already_exists() throws {
        let temporaryPath = try self.temporaryPath()

        let result = try parser.parse([])
        let tuistVersionPath = temporaryPath.appending(component: Constants.versionFileName)
        try "3.2.1".write(to: tuistVersionPath.url, atomically: true, encoding: .utf8)
        let versionPath = versionsController.path(version: "3.2.1")
        try FileHandler.shared.createFolder(versionPath)

        try subject.run(with: result)

        XCTAssertEqual(installer.installCallCount, 0)
    }

    func test_run_prints_the_right_messages() throws {
        let result = try parser.parse([])
        let temporaryPath = try self.temporaryPath()
        let tuistVersionPath = temporaryPath.appending(component: Constants.versionFileName)
        let binPath = temporaryPath.appending(component: Constants.binFolderName)

        try "3.2.1".write(to: tuistVersionPath.url, atomically: true, encoding: .utf8)

        installer.installStub = { version, _ in
            let versionPath = self.versionsController.path(version: version)
            try FileHandler.shared.createFolder(versionPath)
            try Data().write(to: versionPath.appending(component: "test").url)
        }

        try subject.run(with: result)

        XCTAssertPrinterOutputContains("""
        Bundling the version 3.2.1 in the directory \(binPath.pathString)
        Version 3.2.1 not available locally. Installing...
        tuist bundled successfully at \(binPath.pathString)
        """)
    }
}
