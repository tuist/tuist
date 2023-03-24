import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator
@testable import TuistSupportTesting

final class EnvironmentLinterTests: TuistUnitTestCase {
    private var rootDirectoryLocator: MockRootDirectoryLocator!
    var subject: EnvironmentLinter!

    override func setUp() {
        super.setUp()

        rootDirectoryLocator = MockRootDirectoryLocator()
        subject = EnvironmentLinter(rootDirectoryLocator: rootDirectoryLocator)
    }

    override func tearDown() {
        subject = nil
        rootDirectoryLocator = nil
        super.tearDown()
    }

    func test_lintXcodeVersion_doesntReturnIssues_theVersionsOfXcodeAreCompatible() throws {
        // Given
        let configs = [
            Config.test(compatibleXcodeVersions: "4.3.2"),
            Config.test(compatibleXcodeVersions: .exact("4.3.2")),
            Config.test(compatibleXcodeVersions: .upToNextMajor("4.0")),
            Config.test(compatibleXcodeVersions: .upToNextMinor("4.3")),
            Config.test(compatibleXcodeVersions: ["1.0", "4.3.2"]),
        ]

        xcodeController.selectedStub = .success(Xcode.test(infoPlist: .test(version: "4.3.2")))

        // When
        let got = try configs.flatMap { try subject.lintXcodeVersion(config: $0) }

        // Then
        XCTEmpty(got)
    }

    func test_lintXcodeVersion_returnsALintingIssue_when_theVersionsOfXcodeAreIncompatible() throws {
        // Given
        let configs = [
            Config.test(compatibleXcodeVersions: "4.3.1"),
            Config.test(compatibleXcodeVersions: .exact("4.3.1")),
            Config.test(compatibleXcodeVersions: .upToNextMajor("3.0")),
            Config.test(compatibleXcodeVersions: .upToNextMajor("5.0")),
            Config.test(compatibleXcodeVersions: .upToNextMinor("4.2.0")),
            Config.test(compatibleXcodeVersions: .upToNextMinor("4.3.3")),
            Config.test(compatibleXcodeVersions: ["4.3", "4.3.3"]),
            Config.test(compatibleXcodeVersions: .list(["3.2.1"])),
        ]

        xcodeController.selectedStub = .success(Xcode.test(infoPlist: .test(version: "4.3.2")))

        for config in configs {
            // When
            let got = try subject.lintXcodeVersion(config: config)

            // Then
            let expectedMessage =
                "The selected Xcode version is 4.3.2, which is not compatible with this project's Xcode version requirement of \(config.compatibleXcodeVersions)."
            XCTAssertTrue(got.contains(LintingIssue(reason: expectedMessage, severity: .error)))
        }
    }

    func test_lintXcodeVersion_doesntReturnIssues_whenAllVersionsAreSupported() throws {
        // Given
        let config = Config.test(compatibleXcodeVersions: .all)
        xcodeController.selectedStub = .success(Xcode.test(infoPlist: .test(version: "4.3.2")))

        // When
        let got = try subject.lintXcodeVersion(config: config)

        // Then
        XCTEmpty(got)
    }

    func test_lintXcodeVersion_doesntReturnIssues_whenThereIsNoSelectedXcode() throws {
        // Given
        let config = Config.test(compatibleXcodeVersions: .list(["3.2.1"]))

        // When
        let got = try subject.lintXcodeVersion(config: config)

        // Then
        XCTEmpty(got)
    }

    func test_lintXcodeVersion_throws_when_theSelectedXcodeCantBeObtained() throws {
        // Given
        let config = Config.test(compatibleXcodeVersions: .list(["3.2.1"]))
        let error = NSError.test()
        xcodeController.selectedStub = .failure(error)

        // Then
        XCTAssertThrowsError(try subject.lintXcodeVersion(config: config)) {
            XCTAssertEqual($0 as NSError, error)
        }
    }

    func test_lintConfigPath_returnsALintingIssue_when_configManifestIsNotLocatedAtTuistDirectory() {
        // Given
        let fakeRoot = try! AbsolutePath(validating: "/root")
        rootDirectoryLocator.locateStub = fakeRoot

        let configPath = fakeRoot.appending(RelativePath("Config.swift"))
        let config = Config.test(path: configPath)

        // When
        let got = subject.lintConfigPath(config: config)

        // Then
        let expectedMessage = "`Config.swift` manifest file is not located at `Tuist` directory"
        XCTAssertTrue(got.contains(LintingIssue(reason: expectedMessage, severity: .warning)))
    }

    func test_lintConfigPath_doesntReturnALintingIssue_when_configManifestIsLocatedAtTuistDirectory() {
        // Given
        let fakeRoot = try! AbsolutePath(validating: "/root")
        rootDirectoryLocator.locateStub = fakeRoot

        let configPath = fakeRoot
            .appending(RelativePath("\(Constants.tuistDirectoryName)"))
            .appending(RelativePath("Config.swift"))
        let config = Config.test(path: configPath)

        // When
        let got = subject.lintConfigPath(config: config)

        // Then
        XCTEmpty(got)
    }
}
