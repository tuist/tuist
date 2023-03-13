import Foundation
import TSCBasic
import XCTest
@testable import TuistEnvKit
@testable import TuistSupport
@testable import TuistSupportTesting

final class BundleServiceErrorTests: XCTestCase {
    func test_type() throws {
        let path = try AbsolutePath(validating: "/test")
        XCTAssertEqual(BundleServiceError.missingVersionFile(path).type, .abort)
    }

    func test_description() throws {
        let path = try AbsolutePath(validating: "/test")
        XCTAssertEqual(
            BundleServiceError.missingVersionFile(path).description,
            "Couldn't find a .tuist-version file in the directory \(path.pathString)"
        )
    }
}

final class BundleServiceTests: TuistUnitTestCase {
    var versionsController: MockVersionsController!
    var installer: MockInstaller!
    var subject: BundleService!
    var tmpDir: TemporaryDirectory!

    override func setUp() {
        super.setUp()
        versionsController = try! MockVersionsController()
        installer = MockInstaller()
        tmpDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
        subject = BundleService(
            versionsController: versionsController,
            installer: installer
        )
    }

    override func tearDown() {
        versionsController = nil
        installer = nil
        subject = nil
        tmpDir = nil
        super.tearDown()
    }

    func test_run_throws_when_there_is_no_xmp_version_in_the_directory() throws {
        let temporaryPath = try temporaryPath()
        XCTAssertThrowsSpecific(try subject.run(), BundleServiceError.missingVersionFile(temporaryPath))
    }

    func test_run_installs_the_app_if_it_doesnt_exist() throws {
        let temporaryPath = try temporaryPath()
        let tuistVersionPath = temporaryPath.appending(component: Constants.versionFileName)
        try "3.2.1".write(to: tuistVersionPath.url, atomically: true, encoding: .utf8)

        installer.installStub = { version in
            let versionPath = try self.versionsController.path(version: version)
            try FileHandler.shared.createFolder(versionPath)
            try Data().write(to: versionPath.appending(component: "test").url)
        }

        try subject.run()

        let bundledTestFilePath = temporaryPath
            .appending(component: Constants.binFolderName)
            .appending(component: "test")

        XCTAssertTrue(FileHandler.shared.exists(bundledTestFilePath))
    }

    func test_run_doesnt_install_the_app_if_it_already_exists() throws {
        let temporaryPath = try temporaryPath()

        let tuistVersionPath = temporaryPath.appending(component: Constants.versionFileName)
        try "3.2.1".write(to: tuistVersionPath.url, atomically: true, encoding: .utf8)
        let versionPath = try versionsController.path(version: "3.2.1")
        try FileHandler.shared.createFolder(versionPath)

        try subject.run()

        XCTAssertEqual(installer.installCallCount, 0)
    }

    func test_run_doesnt_install_the_app_if_it_already_exists_with_whitespace_in_version_file() throws {
        let temporaryPath = try temporaryPath()

        let tuistVersionPath = temporaryPath.appending(component: Constants.versionFileName)
        try "3.2.1\n\t".write(to: tuistVersionPath.url, atomically: true, encoding: .utf8)
        let versionPath = try versionsController.path(version: "3.2.1")
        try FileHandler.shared.createFolder(versionPath)

        try subject.run()

        XCTAssertEqual(installer.installCallCount, 0)
    }

    func test_run_prints_the_right_messages() throws {
        let temporaryPath = try temporaryPath()
        let tuistVersionPath = temporaryPath.appending(component: Constants.versionFileName)
        let binPath = temporaryPath.appending(component: Constants.binFolderName)

        try "3.2.1".write(to: tuistVersionPath.url, atomically: true, encoding: .utf8)

        installer.installStub = { version in
            let versionPath = try self.versionsController.path(version: version)
            try FileHandler.shared.createFolder(versionPath)
            try Data().write(to: versionPath.appending(component: "test").url)
        }

        try subject.run()

        XCTAssertPrinterOutputContains("""
        Bundling the version 3.2.1 in the directory \(binPath.pathString)
        Version 3.2.1 not available locally. Installing...
        tuist bundled successfully at \(binPath.pathString)
        """)
    }
}
