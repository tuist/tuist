import Foundation
import TSCBasic
import TuistCore
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

    func test_lintXcodeVersion_returnsALintingIssue_when_theVersionsOfXcodeAreIncompatible() throws {
        // Given
        let config = Config.test(compatibleXcodeVersions: .list(["3.2.1"]))
        xcodeController.selectedStub = .success(Xcode.test(infoPlist: .test(version: "4.3.2")))

        // When
        let got = try subject.lintXcodeVersion(config: config)

        // Then
        let expectedMessage = "The project, which only supports the versions of Xcode 3.2.1, is not compatible with your selected version of Xcode, 4.3.2"
        XCTAssertTrue(got.contains(LintingIssue(reason: expectedMessage, severity: .error)))
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
        let fakeRoot = AbsolutePath("/root")
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
        let fakeRoot = AbsolutePath("/root")
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
