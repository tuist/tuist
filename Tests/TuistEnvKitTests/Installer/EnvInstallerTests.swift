import Foundation
import TSCBasic
import TuistSupport
import XCTest
@testable import TuistEnvKit
@testable import TuistSupportTesting

final class EnvInstallerTests: TuistUnitTestCase {
    var buildCopier: MockBuildCopier!
    var versionsController: MockVersionsController!
    var subject: EnvInstaller!
    var tmpDir: TemporaryDirectory!

    override func setUp() {
        super.setUp()
        buildCopier = MockBuildCopier()
        versionsController = try! MockVersionsController()
        tmpDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
        subject = EnvInstaller(
            buildCopier: buildCopier,
            versionsController: versionsController
        )
    }

    override func tearDown() {
        buildCopier = nil
        versionsController = nil
        tmpDir = nil
        subject = nil
        super.tearDown()
    }

    func test_install_when_bundled_release() throws {
        let version = "3.2.1"
        let temporaryPath = try temporaryPath()
        stubLocalAndRemoveSwiftVersions()
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        let downloadURL = URL(string: "https://github.com/tuist/tuist/releases/download/3.2.1/tuistenv.zip")!

        versionsController.installStub = { _, closure in
            try closure(temporaryPath)
        }

        let downloadPath = temporaryDirectory
            .path
            .appending(component: Constants.envBundleName)
        system.whichStub = { _ in "/path/to/tuist" }
        system.succeedCommand([
            "/usr/bin/curl",
            "-LSs",
            "--output",
            downloadPath.pathString,
            downloadURL.absoluteString,
        ])
        system.succeedCommand([
            "/usr/bin/unzip",
            "-q",
            downloadPath.pathString,
            "tuistenv",
            "-d",
            temporaryDirectory.path.pathString,
        ])
        system.succeedCommand([
            "cp",
            temporaryDirectory.path.appending(component: "tuistenv").pathString,
            "/path/to/tuist",
        ])

        try subject.install(
            version: version,
            temporaryDirectory: temporaryDirectory.path
        )

        XCTAssertPrinterOutputContains("""
        Downloading TuistEnv version 3.2.1
        Installing…
        TuistEnv Version \(version) installed
        """)
    }

    func test_install_when_cp_fails() throws {
        let version = "3.2.1"
        let temporaryPath = try temporaryPath()
        stubLocalAndRemoveSwiftVersions()
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        let downloadURL = URL(string: "https://github.com/tuist/tuist/releases/download/3.2.1/tuistenv.zip")!

        versionsController.installStub = { _, closure in
            try closure(temporaryPath)
        }

        let downloadPath = temporaryDirectory
            .path
            .appending(component: Constants.envBundleName)
        system.whichStub = { _ in "/path/to/tuist" }
        system.succeedCommand([
            "/usr/bin/curl",
            "-LSs",
            "--output",
            downloadPath.pathString,
            downloadURL.absoluteString,
        ])
        system.succeedCommand([
            "/usr/bin/unzip",
            "-q",
            downloadPath.pathString,
            "tuistenv",
            "-d",
            temporaryDirectory.path.pathString,
        ])
        system.succeedCommand([
            "sudo",
            "cp",
            temporaryDirectory.path.appending(component: "tuistenv").pathString,
            "/path/to/tuist",
        ])

        try subject.install(
            version: version,
            temporaryDirectory: temporaryDirectory.path
        )

        XCTAssertPrinterOutputContains("""
        Downloading TuistEnv version 3.2.1
        Installing…
        TuistEnv Version \(version) installed
        """)
    }

    func test_install_when_bundled_release_and_download_fails() throws {
        let temporaryPath = try temporaryPath()
        let version = "3.2.1"
        stubLocalAndRemoveSwiftVersions()
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        let downloadURL = URL(string: "https://github.com/tuist/tuist/releases/download/3.2.1/tuistenv.zip")!

        versionsController.installStub = { _, closure in
            try closure(temporaryPath)
        }

        let downloadPath = temporaryDirectory
            .path
            .appending(component: Constants.envBundleName)
        system.whichStub = { _ in "/path/to/tuist" }
        system.errorCommand(
            [
                "/usr/bin/curl",
                "-LSs",
                "--output",
                downloadPath.pathString,
                downloadURL.absoluteString,
            ],
            error: "download_error"
        )

        let expectedError = TuistSupport.SystemError.terminated(
            command: "/usr/bin/curl",
            code: 1,
            standardError: Data("download_error".utf8)
        )
        XCTAssertThrowsSpecific(try subject.install(version: version, temporaryDirectory: temporaryDirectory.path), expectedError)
    }

    func test_install_when_bundled_release_when_unzip_fails() throws {
        let temporaryPath = try temporaryPath()
        let version = "3.2.1"
        stubLocalAndRemoveSwiftVersions()
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        let downloadURL = URL(string: "https://github.com/tuist/tuist/releases/download/3.2.1/tuistenv.zip")!

        versionsController.installStub = { _, closure in
            try closure(temporaryPath)
        }

        let downloadPath = temporaryDirectory
            .path
            .appending(component: Constants.envBundleName)
        system.whichStub = { _ in "/path/to/tuist" }
        system.succeedCommand([
            "/usr/bin/curl",
            "-LSs",
            "--output",
            downloadPath.pathString,
            downloadURL.absoluteString,
        ])
        system.errorCommand(
            [
                "/usr/bin/unzip",
                "-q",
                downloadPath.pathString,
                "tuistenv",
                "-d",
                temporaryDirectory.path.pathString,
            ],
            error: "unzip_error"
        )

        let expectedError = TuistSupport.SystemError.terminated(
            command: "/usr/bin/unzip",
            code: 1,
            standardError: Data("unzip_error".utf8)
        )
        XCTAssertThrowsSpecific(try subject.install(version: version, temporaryDirectory: temporaryDirectory.path), expectedError)
    }

    // MARK: - Fileprivate

    fileprivate func stubLocalAndRemoveSwiftVersions() {
        system.swiftVersionStub = { "5.0.0" }
    }
}
