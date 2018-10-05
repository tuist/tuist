import Basic
import Foundation
import TuistCore
@testable import TuistCoreTesting
@testable import TuistEnvKit
import TuistShared
import Utility
import XCTest

final class InstallerTests: XCTestCase {
    var printer: MockPrinter!
    var fileHandler: MockFileHandler!
    var buildCopier: MockBuildCopier!
    var versionsController: MockVersionsController!
    var subject: Installer!
    var tmpDir: TemporaryDirectory!
    var system: MockSystem!
    var githubClient: MockGitHubClient!

    override func setUp() {
        super.setUp()
        system = MockSystem()
        printer = MockPrinter()
        fileHandler = try! MockFileHandler()
        buildCopier = MockBuildCopier()
        versionsController = try! MockVersionsController()
        tmpDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
        githubClient = MockGitHubClient()
        subject = Installer(system: system,
                            printer: printer,
                            fileHandler: fileHandler,
                            buildCopier: buildCopier,
                            versionsController: versionsController,
                            githubClient: githubClient)
    }

    func test_install_when_invalid_swift_version() throws {
        let version = "3.2.1"
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        system.swiftVersionStub = { "8.8.8" }
        githubClient.getContentStub = { ref, path in
            if ref == version && path == ".swift-version" {
                return "7.7.7"
            } else {
                throw NSError.test()
            }
        }

        let expectedError = InstallerError.incompatibleSwiftVersion(local: "8.8.8", expected: "7.7.7")
        XCTAssertThrowsError(try subject.install(version: version,
                                                 temporaryDirectory: temporaryDirectory)) { error in
            XCTAssertEqual(error as? InstallerError, expectedError)
        }
        XCTAssertTrue(printer.printArgs.contains("Verifying the Swift version is compatible with your version 8.8.8"))
    }

    func test_install_when_bundled_release() throws {
        let version = "3.2.1"
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        let downloadURL = URL(string: "https://test.com/tuist.zip")!
        let asset = Release.Asset(downloadURL: downloadURL,
                                  name: "tuist.zip")
        let release = Release.test(assets: [asset])
        githubClient.releaseWithTagStub = {
            if $0 == version { return release }
            else { throw NSError.test() }
        }

        versionsController.installStub = { _, closure in
            try closure(self.fileHandler.currentPath)
        }

        let downloadPath = temporaryDirectory
            .path
            .appending(component: Constants.bundleName)
        system.stub(args: [
            "curl", "-LSs",
            "--output", downloadPath.asString,
            downloadURL.absoluteString,
        ],
                    stderror: nil,
                    stdout: nil,
                    exitstatus: 0)
        system.stub(args: [
            "unzip", downloadPath.asString,
            "-d", self.fileHandler.currentPath.asString,
        ],
                    stderror: nil,
                    stdout: nil,
                    exitstatus: 0)

        try subject.install(version: version,
                            temporaryDirectory: temporaryDirectory)

        XCTAssertEqual(printer.printArgs.count, 3)
        XCTAssertEqual(printer.printArgs[0], "Downloading version from \(downloadURL.absoluteString)")
        XCTAssertEqual(printer.printArgs[1], "Installing...")
        XCTAssertEqual(printer.printArgs[2], "Version \(version) installed")

        let tuistVersionPath = fileHandler.currentPath.appending(component: Constants.versionFileName)
        XCTAssertTrue(fileHandler.exists(tuistVersionPath))
    }

    func test_install_when_bundled_release_and_download_fails() throws {
        let version = "3.2.1"
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        let downloadURL = URL(string: "https://test.com/tuist.zip")!
        let asset = Release.Asset(downloadURL: downloadURL,
                                  name: "tuist.zip")
        let release = Release.test(assets: [asset])
        githubClient.releaseWithTagStub = {
            if $0 == version { return release }
            else { throw NSError.test() }
        }

        versionsController.installStub = { _, closure in
            try closure(self.fileHandler.currentPath)
        }

        let downloadPath = temporaryDirectory
            .path
            .appending(component: Constants.bundleName)
        system.stub(args: [
            "curl", "-LSs",
            "--output", downloadPath.asString,
            downloadURL.absoluteString,
        ],
                    stderror: "download_error",
                    stdout: nil,
                    exitstatus: 1)

        let expected = SystemError(stderror: "download_error", exitcode: 1)
        XCTAssertThrowsError(try subject.install(version: version,
                                                 temporaryDirectory: temporaryDirectory)) {
            XCTAssertEqual($0 as? SystemError, expected)
        }
    }

    func test_install_when_bundled_release_when_unzip_fails() throws {
        let version = "3.2.1"
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        let downloadURL = URL(string: "https://test.com/tuist.zip")!
        let asset = Release.Asset(downloadURL: downloadURL,
                                  name: "tuist.zip")
        let release = Release.test(assets: [asset])
        githubClient.releaseWithTagStub = {
            if $0 == version { return release }
            else { throw NSError.test() }
        }

        versionsController.installStub = { _, closure in
            try closure(self.fileHandler.currentPath)
        }

        let downloadPath = temporaryDirectory
            .path
            .appending(component: Constants.bundleName)
        system.stub(args: [
            "curl", "-LSs",
            "--output", downloadPath.asString,
            downloadURL.absoluteString,
        ],
                    stderror: nil,
                    stdout: nil,
                    exitstatus: 0)
        system.stub(args: [
            "unzip", downloadPath.asString,
            "-d", self.fileHandler.currentPath.asString,
        ],
                    stderror: "unzip_error",
                    stdout: nil,
                    exitstatus: 1)

        let expected = SystemError(stderror: "unzip_error", exitcode: 1)
        XCTAssertThrowsError(try subject.install(version: version,
                                                 temporaryDirectory: temporaryDirectory)) {
            XCTAssertEqual($0 as? SystemError, expected)
        }
    }

    func test_install_when_no_bundled_release() throws {
        let version = "3.2.1"
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)

        versionsController.installStub = { _, closure in
            try closure(self.fileHandler.currentPath)
        }

        system.stub(args: [
            "git",
            "clone", Constants.gitRepositoryURL,
            temporaryDirectory.path.asString,
        ],
                    stderror: nil,
                    stdout: nil,
                    exitstatus: 0)
        system.stub(args: [
            "git", "-C", temporaryDirectory.path.asString,
            "checkout", version,
        ],
                    stderror: nil,
                    stdout: nil,
                    exitstatus: 0)
        system.stub(args: ["/usr/bin/xcrun", "-f", "swift"],
                    stderror: nil,
                    stdout: "/path/to/swift",
                    exitstatus: 0)
        system.stub(args: [
            "/path/to/swift", "build",
            "--product", "tuist",
            "--package-path", temporaryDirectory.path.asString,
            "--configuration", "release",
            "-Xswiftc", "-static-stdlib",
        ],
                    stderror: nil,
                    stdout: nil,
                    exitstatus: 0)
        system.stub(args: [
            "/path/to/swift", "build",
            "--product", "ProjectDescription",
            "--package-path", temporaryDirectory.path.asString,
            "--configuration", "release",
        ],
                    stderror: nil,
                    stdout: nil,
                    exitstatus: 0)
        system.stub(args: [
            "/bin/mkdir",
            fileHandler.currentPath.asString,
        ],
                    stderror: nil,
                    stdout: nil,
                    exitstatus: 0)

        try subject.install(version: version, temporaryDirectory: temporaryDirectory)

        XCTAssertEqual(printer.printWarningArgs.count, 1)
        XCTAssertEqual(printer.printWarningArgs.first, "The release \(version) is not bundled")

        XCTAssertEqual(printer.printArgs.count, 3)
        XCTAssertEqual(printer.printArgs[0], "Pulling source code")
        XCTAssertEqual(printer.printArgs[1], "Building using Swift (it might take a while)")
        XCTAssertEqual(printer.printArgs[2], "Version 3.2.1 installed")

        let tuistVersionPath = fileHandler.currentPath.appending(component: Constants.versionFileName)
        XCTAssertTrue(fileHandler.exists(tuistVersionPath))
    }

    func test_install_when_no_bundled_release_and_invalid_reference() throws {
        let version = "3.2.1"
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)

        versionsController.installStub = { _, closure in
            try closure(self.fileHandler.currentPath)
        }

        system.stub(args: [
            "git",
            "clone", Constants.gitRepositoryURL,
            temporaryDirectory.path.asString,
        ],
                    stderror: nil,
                    stdout: nil,
                    exitstatus: 0)
        system.stub(args: [
            "git", "-C", temporaryDirectory.path.asString,
            "checkout", version,
        ],
                    stderror: "did not match any file(s) known to git ",
                    stdout: nil,
                    exitstatus: 1)

        let expected = InstallerError.versionNotFound(version)
        XCTAssertThrowsError(try subject.install(version: version, temporaryDirectory: temporaryDirectory)) {
            XCTAssertEqual($0 as? InstallerError, expected)
        }
    }
}
