import Basic
import Foundation
import SPMUtility
import TuistCore
import XCTest
@testable import TuistCoreTesting
@testable import TuistEnvKit

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

    func test_install_when_bundled_release_with_sentry() throws {
        // Given
        let version = "3.2.1"
        stubLocalAndRemoveSwiftVersions()
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        let tuistDownloadURL = URL(string: "https://test.com/tuist.zip")!
        let sentryDownloadURL = URL(string: "https://test.com/Sentry.framework.zip")!

        let tuistAsset = Release.Asset(downloadURL: tuistDownloadURL,
                                       name: "tuist.zip")
        let sentryAsset = Release.Asset(downloadURL: sentryDownloadURL,
                                        name: "Sentry.framework.zip")
        let release = Release.test(assets: [tuistAsset, sentryAsset])

        githubClient.releaseWithTagStub = {
            if $0 == version { return release }
            else { throw NSError.test() }
        }

        versionsController.installStub = { _, closure in
            try closure(self.fileHandler.currentPath)
        }

        let tuistDownloadPath = temporaryDirectory
            .path
            .appending(component: Constants.bundleName)
        let sentryDownloadPath = temporaryDirectory
            .path
            .appending(component: Constants.sentryBundleName)

        system.succeedCommand("/usr/bin/curl", "-LSs",
                              "--output", tuistDownloadPath.pathString,
                              tuistDownloadURL.absoluteString)
        system.succeedCommand("/usr/bin/curl", "-LSs",
                              "--output", sentryDownloadPath.pathString,
                              sentryDownloadURL.absoluteString)
        system.succeedCommand("/usr/bin/unzip",
                              "-q",
                              tuistDownloadPath.pathString,
                              "-d", fileHandler.currentPath.pathString)
        system.succeedCommand("/usr/bin/unzip",
                              "-q",
                              sentryDownloadPath.pathString,
                              "-d", fileHandler.currentPath.pathString)

        // When
        try subject.install(version: version,
                            temporaryDirectory: temporaryDirectory)

        // Then
        XCTAssertEqual(printer.printArgs.count, 3)
        XCTAssertEqual(printer.printArgs[0], "Downloading version from \(tuistDownloadURL.absoluteString)")
        XCTAssertEqual(printer.printArgs[1], "Installing...")
        XCTAssertEqual(printer.printArgs[2], "Version \(version) installed")

        let tuistVersionPath = fileHandler.currentPath.appending(component: Constants.versionFileName)
        XCTAssertTrue(fileHandler.exists(tuistVersionPath))
    }

    func test_install_when_bundled_release() throws {
        // Given
        let version = "3.2.1"
        stubLocalAndRemoveSwiftVersions()
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        let tuistDownloadURL = URL(string: "https://test.com/tuist.zip")!

        let tuistAsset = Release.Asset(downloadURL: tuistDownloadURL,
                                       name: "tuist.zip")
        let release = Release.test(assets: [tuistAsset])

        githubClient.releaseWithTagStub = {
            if $0 == version { return release }
            else { throw NSError.test() }
        }

        versionsController.installStub = { _, closure in
            try closure(self.fileHandler.currentPath)
        }

        let tuistDownloadPath = temporaryDirectory
            .path
            .appending(component: Constants.bundleName)

        system.succeedCommand("/usr/bin/curl", "-LSs",
                              "--output", tuistDownloadPath.pathString,
                              tuistDownloadURL.absoluteString)
        system.succeedCommand("/usr/bin/unzip",
                              "-q",
                              tuistDownloadPath.pathString,
                              "-d", fileHandler.currentPath.pathString)

        // When
        try subject.install(version: version,
                            temporaryDirectory: temporaryDirectory)

        // Then
        XCTAssertEqual(printer.printArgs.count, 3)
        XCTAssertEqual(printer.printArgs[0], "Downloading version from \(tuistDownloadURL.absoluteString)")
        XCTAssertEqual(printer.printArgs[1], "Installing...")
        XCTAssertEqual(printer.printArgs[2], "Version \(version) installed")

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
        // Given
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

        let tuistPath = temporaryDirectory.path.appending(RelativePath(".build/release/tuist"))
        system.succeedCommand(["install_name_tool",
                               "-add_rpath", "@executable_path",
                               tuistPath.pathString])
        system.succeedCommand("/path/to/swift", "build",
                              "--product", "ProjectDescription",
                              "--package-path", temporaryDirectory.path.pathString,
                              "--configuration", "release")

        // When
        try subject.install(version: version, temporaryDirectory: temporaryDirectory)

        // Then
        XCTAssertEqual(printer.printWarningArgs.count, 1)
        XCTAssertEqual(printer.printWarningArgs.first, "The release \(version) is not bundled")
        XCTAssertEqual(printer.printArgs.count, 3)
        XCTAssertEqual(printer.printArgs[0], "Pulling source code")
        XCTAssertEqual(printer.printArgs[1], "Building using Swift (it might take a while)")
        XCTAssertEqual(printer.printArgs[2], "Version 3.2.1 installed")
        let tuistVersionPath = installationDirectory.appending(component: Constants.versionFileName)
        XCTAssertTrue(fileHandler.exists(tuistVersionPath))
        XCTAssertEqual(buildCopier.copyFrameworksArgs.count, 1)
        XCTAssertEqual(buildCopier.copyFrameworksArgs.first!.from, temporaryDirectory.path.appending(component: "Frameworks"))
        XCTAssertEqual(buildCopier.copyFrameworksArgs.first!.to, installationDirectory)
    }

    func test_install_when_force() throws {
        // Given
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
        let tuistPath = temporaryDirectory.path.appending(RelativePath(".build/release/tuist"))
        system.succeedCommand(["install_name_tool",
                               "-add_rpath", "@executable_path",
                               tuistPath.pathString])
        system.succeedCommand("/path/to/swift", "build",
                              "--product", "ProjectDescription",
                              "--package-path", temporaryDirectory.path.pathString,
                              "--configuration", "release")

        // When
        try subject.install(version: version, temporaryDirectory: temporaryDirectory, force: true)

        // Then
        XCTAssertEqual(printer.printArgs.count, 4)
        XCTAssertEqual(printer.printArgs[0], "Forcing the installation of 3.2.1 from the source code")
        XCTAssertEqual(printer.printArgs[1], "Pulling source code")
        XCTAssertEqual(printer.printArgs[2], "Building using Swift (it might take a while)")
        XCTAssertEqual(printer.printArgs[3], "Version 3.2.1 installed")
        let tuistVersionPath = installationDirectory.appending(component: Constants.versionFileName)
        XCTAssertTrue(fileHandler.exists(tuistVersionPath))
        XCTAssertEqual(buildCopier.copyFrameworksArgs.count, 1)
        XCTAssertEqual(buildCopier.copyFrameworksArgs.first!.from, temporaryDirectory.path.appending(component: "Frameworks"))
        XCTAssertEqual(buildCopier.copyFrameworksArgs.first!.to, installationDirectory)
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
