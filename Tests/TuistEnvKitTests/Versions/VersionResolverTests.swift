import Foundation
import TSCBasic
import TuistSupport
import TuistSupportTesting
import XCTest
@testable import TuistEnvKit

final class VersionResolverErrorTests: XCTestCase {
    func test_errorDescription() {
        let path = AbsolutePath("/test")
        XCTAssertEqual(VersionResolverError.readError(path: path).description, "Cannot read the version file at path /test.")
    }

    func test_equatable() {
        let path = AbsolutePath("/test")
        XCTAssertEqual(VersionResolverError.readError(path: path), VersionResolverError.readError(path: path))
    }
}

final class VersionResolverTests: XCTestCase {
    var subject: VersionResolver!
    var settingsController: MockSettingsController!

    override func setUp() {
        super.setUp()
        settingsController = MockSettingsController()
        subject = VersionResolver(settingsController: settingsController)
    }

    override func tearDown() {
        settingsController = nil
        subject = nil
        super.tearDown()
    }

    func test_resolve_when_version_and_bin() throws {
        let tmp_dir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let versionPath = tmp_dir.path.appending(component: Constants.versionFileName)
        let binPath = tmp_dir.path.appending(component: Constants.binFolderName)

        // /tmp/dir/.tuist-version
        try "3.2.1".write(
            to: URL(fileURLWithPath: versionPath.pathString),
            atomically: true,
            encoding: .utf8
        )
        // /tmp/dir/.tuist-bin
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: binPath.pathString),
            withIntermediateDirectories: true,
            attributes: nil
        )

        let got = try subject.resolve(path: tmp_dir.path)
        XCTAssertEqual(got, .bin(binPath))
    }

    func test_resolve_when_version() throws {
        let tmp_dir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let versionPath = tmp_dir.path.appending(component: Constants.versionFileName)

        // /tmp/dir/.tuist-version
        try "3.2.1".write(
            to: URL(fileURLWithPath: versionPath.pathString),
            atomically: true,
            encoding: .utf8
        )

        let got = try subject.resolve(path: tmp_dir.path)
        XCTAssertEqual(got, .versionFile(versionPath, "3.2.1"))
    }

    func test_resolve_when_version_contains_trailing_whitespace() throws {
        let tmp_dir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let versionPath = tmp_dir.path.appending(component: Constants.versionFileName)

        // /tmp/dir/.tuist-version
        try "3.2.1 \n".write(
            to: URL(fileURLWithPath: versionPath.pathString),
            atomically: true,
            encoding: .utf8
        )

        let got = try subject.resolve(path: tmp_dir.path)
        XCTAssertEqual(got, .versionFile(versionPath, "3.2.1"))
    }

    func test_resolve_when_bin() throws {
        let tmp_dir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let binPath = tmp_dir.path.appending(component: Constants.binFolderName)

        // /tmp/dir/.tuist-bin
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: binPath.pathString),
            withIntermediateDirectories: true,
            attributes: nil
        )

        let got = try subject.resolve(path: tmp_dir.path)
        XCTAssertEqual(got, .bin(binPath))
    }

    func test_resolve_when_version_in_parent_directory() throws {
        let tmp_dir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let versionPath = tmp_dir.path.appending(component: Constants.versionFileName)
        let childPath = tmp_dir.path.appending(component: "child")

        // /tmp/dir/.tuist-version
        try "3.2.1".write(
            to: URL(fileURLWithPath: versionPath.pathString),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: childPath.pathString),
            withIntermediateDirectories: true,
            attributes: nil
        )

        let got = try subject.resolve(path: childPath)
        XCTAssertEqual(got, .versionFile(versionPath, "3.2.1"))
    }

    func test_resolve_when_bin_in_parent_directory() throws {
        let tmp_dir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let binPath = tmp_dir.path.appending(component: Constants.binFolderName)
        let childPath = tmp_dir.path.appending(component: "child")

        // /tmp/dir/.tuist-bin
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: binPath.pathString),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: childPath.pathString),
            withIntermediateDirectories: true,
            attributes: nil
        )

        let got = try subject.resolve(path: childPath)
        XCTAssertEqual(got, .bin(binPath))
    }
}
