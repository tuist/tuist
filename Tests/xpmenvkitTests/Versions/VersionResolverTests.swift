import Basic
import Foundation
import XCTest
import xpmcore
@testable import xpmenvkit

final class VersionResolverErrorTests: XCTestCase {
    func test_errorDescription() {
        let path = AbsolutePath("/test")
        XCTAssertEqual(VersionResolverError.readError(path: path).description, "Cannot read the version file at path /test.")
        XCTAssertEqual(VersionResolverError.invalidFormat("3.2", path: path).description, "The version 3.2 at path /test doesn't have a valid semver format: x.y.z.")
    }

    func test_equatable() {
        let path = AbsolutePath("/test")
        XCTAssertEqual(VersionResolverError.readError(path: path), VersionResolverError.readError(path: path))
        XCTAssertEqual(VersionResolverError.invalidFormat("3.2", path: path), VersionResolverError.invalidFormat("3.2", path: path))
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

    func test_resolve_when_canary_defined() throws {
        let tmp_dir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let reference = "reference"

        settingsController.settingsStub = Settings(canaryReference: reference)

        let got = try subject.resolve(path: tmp_dir.path)

        XCTAssertEqual(got, ResolvedVersion.reference(reference))
    }

    func test_resolve_when_version_and_bin() throws {
        let tmp_dir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let versionPath = tmp_dir.path.appending(component: Constants.versionFileName)
        let binPath = tmp_dir.path.appending(component: Constants.binFolderName)

        // /tmp/dir/.xpm-version
        try "3.2.1".write(to: URL(fileURLWithPath: versionPath.asString),
                          atomically: true,
                          encoding: .utf8)
        // /tmp/dir/.xpm-bin
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: binPath.asString),
                                                withIntermediateDirectories: true,
                                                attributes: nil)

        let got = try subject.resolve(path: tmp_dir.path)
        XCTAssertEqual(got, .bin(binPath))
    }

    func test_resolve_when_version() throws {
        let tmp_dir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let versionPath = tmp_dir.path.appending(component: Constants.versionFileName)

        // /tmp/dir/.xpm-version
        try "3.2.1".write(to: URL(fileURLWithPath: versionPath.asString),
                          atomically: true,
                          encoding: .utf8)

        let got = try subject.resolve(path: tmp_dir.path)
        XCTAssertEqual(got, .reference("3.2.1"))
    }

    func test_resolve_when_bin() throws {
        let tmp_dir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let binPath = tmp_dir.path.appending(component: Constants.binFolderName)

        // /tmp/dir/.xpm-bin
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: binPath.asString),
                                                withIntermediateDirectories: true,
                                                attributes: nil)

        let got = try subject.resolve(path: tmp_dir.path)
        XCTAssertEqual(got, .bin(binPath))
    }

    func test_resolve_when_version_in_parent_directory() throws {
        let tmp_dir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let versionPath = tmp_dir.path.appending(component: Constants.versionFileName)
        let childPath = tmp_dir.path.appending(component: "child")

        // /tmp/dir/.xpm-version
        try "3.2.1".write(to: URL(fileURLWithPath: versionPath.asString),
                          atomically: true,
                          encoding: .utf8)
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: childPath.asString),
                                                withIntermediateDirectories: true,
                                                attributes: nil)

        let got = try subject.resolve(path: childPath)
        XCTAssertEqual(got, .reference("3.2.1"))
    }

    func test_resolve_when_bin_in_parent_directory() throws {
        let tmp_dir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let binPath = tmp_dir.path.appending(component: Constants.binFolderName)
        let childPath = tmp_dir.path.appending(component: "child")

        // /tmp/dir/.xpm-bin
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: binPath.asString),
                                                withIntermediateDirectories: true,
                                                attributes: nil)
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: childPath.asString),
                                                withIntermediateDirectories: true,
                                                attributes: nil)

        let got = try subject.resolve(path: childPath)
        XCTAssertEqual(got, .bin(binPath))
    }
}
