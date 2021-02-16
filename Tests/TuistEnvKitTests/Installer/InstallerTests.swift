import Foundation
import TSCBasic
import TuistSupport
import XCTest
@testable import TuistEnvKit
@testable import TuistSupportTesting

final class InstallerTests: TuistUnitTestCase {
    var buildCopier: MockBuildCopier!
    var versionsController: MockVersionsController!
    var subject: Installer!
    var tmpDir: TemporaryDirectory!
    var googleCloudStorageClient: MockGoogleCloudStorageClient!

    override func setUp() {
        super.setUp()
        buildCopier = MockBuildCopier()
        versionsController = try! MockVersionsController()
        tmpDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
        googleCloudStorageClient = MockGoogleCloudStorageClient()
        subject = Installer(buildCopier: buildCopier,
                            versionsController: versionsController,
                            googleCloudStorageClient: googleCloudStorageClient)
    }

    override func tearDown() {
        super.tearDown()
        buildCopier = nil
        versionsController = nil
        tmpDir = nil
        googleCloudStorageClient = nil
        subject = nil
    }

    func test_install_when_bundled_release() throws {
        let version = "3.2.1"
        let temporaryPath = try self.temporaryPath()
        stubLocalAndRemoveSwiftVersions()
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        let downloadURL = URL(string: "https://test.com/tuist.zip")!

        googleCloudStorageClient.tuistBundleURLStub = {
            if $0 == version { return downloadURL }
            else { return nil }
        }

        versionsController.installStub = { _, closure in
            try closure(temporaryPath)
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
                              "-d", temporaryPath.pathString)

        try subject.install(version: version,
                            temporaryDirectory: temporaryDirectory.path)

        XCTAssertPrinterOutputContains("""
        Downloading version 3.2.1
        Installing...
        Version \(version) installed
        """)

        let tuistVersionPath = temporaryPath.appending(component: Constants.versionFileName)
        XCTAssertTrue(FileHandler.shared.exists(tuistVersionPath))
    }

    func test_install_when_bundled_release_and_download_fails() throws {
        let temporaryPath = try self.temporaryPath()
        let version = "3.2.1"
        stubLocalAndRemoveSwiftVersions()
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        let downloadURL = URL(string: "https://test.com/tuist.zip")!

        googleCloudStorageClient.tuistBundleURLStub = {
            if $0 == version { return downloadURL }
            else { return nil }
        }

        versionsController.installStub = { _, closure in
            try closure(temporaryPath)
        }

        let downloadPath = temporaryDirectory
            .path
            .appending(component: Constants.bundleName)
        system.errorCommand("/usr/bin/curl", "-LSs",
                            "--output", downloadPath.pathString,
                            downloadURL.absoluteString,
                            error: "download_error")

        XCTAssertThrowsError(try subject.install(version: version, temporaryDirectory: temporaryDirectory.path))
    }

    func test_install_when_bundled_release_when_unzip_fails() throws {
        let temporaryPath = try self.temporaryPath()
        let version = "3.2.1"
        stubLocalAndRemoveSwiftVersions()
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        let downloadURL = URL(string: "https://test.com/tuist.zip")!
        googleCloudStorageClient.tuistBundleURLStub = {
            if $0 == version { return downloadURL }
            else { return nil }
        }

        versionsController.installStub = { _, closure in
            try closure(temporaryPath)
        }

        let downloadPath = temporaryDirectory
            .path
            .appending(component: Constants.bundleName)
        system.succeedCommand("/usr/bin/curl", "-LSs",
                              "--output", downloadPath.pathString,
                              downloadURL.absoluteString)
        system.errorCommand("/usr/bin/unzip", downloadPath.pathString,
                            "-d", temporaryPath.pathString,
                            error: "unzip_error")

        XCTAssertThrowsError(try subject.install(version: version, temporaryDirectory: temporaryDirectory.path))
    }

    func test_install_when_no_bundled_release() throws {
        let version = "3.2.1"
        let temporaryPath = try self.temporaryPath()

        stubLocalAndRemoveSwiftVersions()
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        let installationDirectory = temporaryPath.appending(component: "3.2.1")

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
                              "--configuration", "release",
                              "-Xswiftc", "-enable-library-evolution",
                              "-Xswiftc", "-emit-module-interface",
                              "-Xswiftc", "-emit-module-interface-path",
                              "-Xswiftc", temporaryDirectory.path.appending(RelativePath(".build/release/ProjectDescription.swiftinterface")).pathString)

        try FileHandler.shared.createFolder(temporaryDirectory.path.appending(component: Constants.templatesDirectoryName))
        try FileHandler.shared.createFolder(temporaryDirectory.path.appending(RelativePath(".build/release")))

        try subject.install(version: version, temporaryDirectory: temporaryDirectory.path)

        XCTAssertPrinterOutputContains("""
        Pulling source code
        Building using Swift (it might take a while)
        Version 3.2.1 installed
        """)

        let tuistVersionPath = installationDirectory.appending(component: Constants.versionFileName)
        XCTAssertTrue(FileHandler.shared.exists(tuistVersionPath))
    }

    func test_install_when_force() throws {
        let version = "3.2.1"
        let temporaryPath = try self.temporaryPath()
        stubLocalAndRemoveSwiftVersions()
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        let installationDirectory = temporaryPath.appending(component: "3.2.1")

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
                              "--configuration", "release",
                              "-Xswiftc", "-enable-library-evolution",
                              "-Xswiftc", "-emit-module-interface",
                              "-Xswiftc", "-emit-module-interface-path",
                              "-Xswiftc", temporaryDirectory.path.appending(RelativePath(".build/release/ProjectDescription.swiftinterface")).pathString)

        try FileHandler.shared.createFolder(temporaryDirectory.path.appending(component: Constants.templatesDirectoryName))
        try FileHandler.shared.createFolder(temporaryDirectory.path.appending(RelativePath(".build/release")))

        try subject.install(version: version, temporaryDirectory: temporaryDirectory.path)

        XCTAssertPrinterOutputContains("""
        Forcing the installation of 3.2.1 from the source code
        Pulling source code
        Building using Swift (it might take a while)
        Version 3.2.1 installed
        """)
        let tuistVersionPath = installationDirectory.appending(component: Constants.versionFileName)
        XCTAssertTrue(FileHandler.shared.exists(tuistVersionPath))
    }

    func test_install_when_no_bundled_release_and_no_templates() throws {
        let version = "3.2.1"
        let temporaryPath = try self.temporaryPath()

        stubLocalAndRemoveSwiftVersions()
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        let installationDirectory = temporaryPath.appending(component: "3.2.1")

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
                              "--configuration", "release",
                              "-Xswiftc", "-enable-library-evolution",
                              "-Xswiftc", "-emit-module-interface",
                              "-Xswiftc", "-emit-module-interface-path",
                              "-Xswiftc", temporaryDirectory.path.appending(RelativePath(".build/release/ProjectDescription.swiftinterface")).pathString)

        try FileHandler.shared.createFolder(temporaryDirectory.path.appending(RelativePath(".build/release")))

        try subject.install(version: version, temporaryDirectory: temporaryDirectory.path)

        XCTAssertPrinterOutputContains("""
        Pulling source code
        Building using Swift (it might take a while)
        Version 3.2.1 installed
        """)

        let tuistVersionPath = installationDirectory.appending(component: Constants.versionFileName)
        XCTAssertTrue(FileHandler.shared.exists(tuistVersionPath))
    }

    func test_install_when_no_bundled_release_and_invalid_reference() throws {
        let version = "3.2.1"
        let temporaryPath = try self.temporaryPath()
        stubLocalAndRemoveSwiftVersions()
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)

        versionsController.installStub = { _, closure in
            try closure(temporaryPath)
        }
        system.succeedCommand("/usr/bin/env", "git",
                              "clone", Constants.gitRepositoryURL,
                              temporaryDirectory.path.pathString)
        system.errorCommand("/usr/bin/env", "git", "-C", temporaryDirectory.path.pathString,
                            "checkout", version,
                            error: "did not match any file(s) known to git ")

        let expected = InstallerError.versionNotFound(version)
        XCTAssertThrowsSpecific(try subject.install(version: version, temporaryDirectory: temporaryDirectory.path), expected)
    }

    // MARK: - Fileprivate

    fileprivate func stubLocalAndRemoveSwiftVersions() {
        system.swiftVersionStub = { "5.0.0" }
    }
}
