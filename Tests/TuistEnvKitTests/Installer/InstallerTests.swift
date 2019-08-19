import Basic
import Foundation
import SPMUtility
import TuistCore
import XCTest
@testable import TuistCoreTesting
@testable import TuistEnvKit

final class InstallerTests: XCTestCase {
    var context: MockContext!
    var fileHandler: MockFileHandler!
    var buildCopier: MockBuildCopier!
    var versionsController: MockVersionsController!
    var subject: Installer!
    var tmpDir: TemporaryDirectory!
    var system: MockSystem!
    var githubClient: MockGitHubClient!

    override func setUp() {
        super.setUp()
        context = Context.mockSharedContext()

        system = MockSystem()
        fileHandler = try! MockFileHandler()
        buildCopier = MockBuildCopier()
        versionsController = try! MockVersionsController()
        tmpDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
        githubClient = MockGitHubClient()
        subject = Installer(system: system,
                            fileHandler: fileHandler,
                            buildCopier: buildCopier,
                            versionsController: versionsController,
                            githubClient: githubClient)
    }

    func test_install_when_invalid_swift_version() throws {
        let version = "3.2.1"
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        system.swiftVersionStub = { "4.2.1" }
        githubClient.getContentStub = { ref, path in
            if ref == version, path == ".swift-version" {
                return "5.0.0"
            } else {
                throw NSError.test()
            }
        }

        let expectedError = InstallerError.incompatibleSwiftVersion(local: "4.2.1", expected: "5.0.0")
        XCTAssertThrowsError(try subject.install(version: version,
                                                 temporaryDirectory: temporaryDirectory)) { error in
            XCTAssertEqual(error as? InstallerError, expectedError)
        }
        XCTAssertPrinterOutput(context, expected: "Verifying the Swift version is compatible with your version 4.2.1")
    }

    func test_install_when_bundled_release() throws {
        let version = "3.2.1"
        stubLocalAndRemoveSwiftVersions()
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
        system.succeedCommand("/usr/bin/curl", "-LSs",
                              "--output", downloadPath.pathString,
                              downloadURL.absoluteString)
        system.succeedCommand("/usr/bin/unzip",
                              "-q",
                              downloadPath.pathString,
                              "-d", fileHandler.currentPath.pathString)

        try subject.install(version: version,
                            temporaryDirectory: temporaryDirectory)

        XCTAssertPrinterOutput(context, expected: """
        Verifying the Swift version is compatible with your version 5.0.0
        Downloading version from \(downloadURL.absoluteString)
        Installing...
        Version \(version) installed
        """)

        let tuistVersionPath = fileHandler.currentPath.appending(component: Constants.versionFileName)
        XCTAssertTrue(fileHandler.exists(tuistVersionPath))
    }

    func test_install_when_bundled_release_and_download_fails() throws {
        let version = "3.2.1"
        stubLocalAndRemoveSwiftVersions()
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
        system.errorCommand("/usr/bin/curl", "-LSs",
                            "--output", downloadPath.pathString,
                            downloadURL.absoluteString,
                            error: "download_error")

        XCTAssertThrowsError(try subject.install(version: version, temporaryDirectory: temporaryDirectory))
    }

    func test_install_when_bundled_release_when_unzip_fails() throws {
        let version = "3.2.1"
        stubLocalAndRemoveSwiftVersions()
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
        system.succeedCommand("/usr/bin/curl", "-LSs",
                              "--output", downloadPath.pathString,
                              downloadURL.absoluteString)
        system.errorCommand("/usr/bin/unzip", downloadPath.pathString,
                            "-d", fileHandler.currentPath.pathString,
                            error: "unzip_error")

        XCTAssertThrowsError(try subject.install(version: version, temporaryDirectory: temporaryDirectory))
    }

    func test_install_when_no_bundled_release() throws {
        let version = "3.2.1"
        stubLocalAndRemoveSwiftVersions()
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        let installationDirectory = fileHandler.currentPath.appending(component: "3.2.1")

        versionsController.installStub = { _, closure in
            try closure(installationDirectory)
        }

        system.succeedCommand("/usr/bin/env", "git",
                              "clone", Constants.gitRepositoryURL,
                              temporaryDirectory.path.pathString)
        system.succeedCommand("/usr/bin/env", "git", "-C", temporaryDirectory.path.pathString,
                              "checkout", version)
        system.succeedCommand("/usr/bin/xcrun", "-f", "swift", output: "/path/to/swift")

        system.succeedCommand("/path/to/swift", "build",
                              "--product", "tuist",
                              "--package-path", temporaryDirectory.path.pathString,
                              "--configuration", "release")
        system.succeedCommand("/path/to/swift", "build",
                              "--product", "ProjectDescription",
                              "--package-path", temporaryDirectory.path.pathString,
                              "--configuration", "release")

        try subject.install(version: version, temporaryDirectory: temporaryDirectory)

        XCTAssertPrinterOutput(context, expected: """
        Verifying the Swift version is compatible with your version 5.0.0
        The release \(version) is not bundled
        Pulling source code
        Building using Swift (it might take a while)
        Version 3.2.1 installed
        """)

        let tuistVersionPath = installationDirectory.appending(component: Constants.versionFileName)
        XCTAssertTrue(fileHandler.exists(tuistVersionPath))
    }

    func test_install_when_force() throws {
        let version = "3.2.1"
        stubLocalAndRemoveSwiftVersions()
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        let installationDirectory = fileHandler.currentPath.appending(component: "3.2.1")

        versionsController.installStub = { _, closure in
            try closure(installationDirectory)
        }

        system.succeedCommand("/usr/bin/env", "git",
                              "clone", Constants.gitRepositoryURL,
                              temporaryDirectory.path.pathString)
        system.succeedCommand("/usr/bin/env", "git", "-C", temporaryDirectory.path.pathString,
                              "checkout", version)
        system.succeedCommand("/usr/bin/xcrun", "-f", "swift",
                              output: "/path/to/swift")
        system.succeedCommand("/path/to/swift", "build",
                              "--product", "tuist",
                              "--package-path", temporaryDirectory.path.pathString,
                              "--configuration", "release")
        system.succeedCommand("/path/to/swift", "build",
                              "--product", "ProjectDescription",
                              "--package-path", temporaryDirectory.path.pathString,
                              "--configuration", "release")

        try subject.install(version: version, temporaryDirectory: temporaryDirectory, force: true)

        XCTAssertPrinterOutput(context, expected: """
        Forcing the installation of 3.2.1 from the source code
        Pulling source code
        Building using Swift (it might take a while)
        Version 3.2.1 installed
        """)
        let tuistVersionPath = installationDirectory.appending(component: Constants.versionFileName)
        XCTAssertTrue(fileHandler.exists(tuistVersionPath))
    }

    func test_install_when_no_bundled_release_and_invalid_reference() throws {
        let version = "3.2.1"
        stubLocalAndRemoveSwiftVersions()
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)

        versionsController.installStub = { _, closure in
            try closure(self.fileHandler.currentPath)
        }
        system.succeedCommand("/usr/bin/env", "git",
                              "clone", Constants.gitRepositoryURL,
                              temporaryDirectory.path.pathString)
        system.errorCommand("/usr/bin/env", "git", "-C", temporaryDirectory.path.pathString,
                            "checkout", version,
                            error: "did not match any file(s) known to git ")

        let expected = InstallerError.versionNotFound(version)
        XCTAssertThrowsError(try subject.install(version: version, temporaryDirectory: temporaryDirectory)) {
            XCTAssertEqual($0 as? InstallerError, expected)
        }
    }

    // MARK: - Fileprivate

    fileprivate func stubLocalAndRemoveSwiftVersions() {
        system.swiftVersionStub = { "5.0.0" }
        githubClient.getContentStub = { _, _ in
            "5.2.1"
        }
    }
}
