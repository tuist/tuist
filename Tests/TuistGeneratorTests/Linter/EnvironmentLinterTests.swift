import Foundation
import Mockable
import TuistCore
import TuistSupport
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator
@testable import TuistSupportTesting

final class EnvironmentLinterTests: TuistUnitTestCase {
    private var rootDirectoryLocator: MockRootDirectoryLocating!
    var subject: EnvironmentLinter!

    override func setUp() {
        super.setUp()

        rootDirectoryLocator = .init()
        subject = EnvironmentLinter(rootDirectoryLocator: rootDirectoryLocator)
    }

    override func tearDown() {
        subject = nil
        rootDirectoryLocator = nil
        super.tearDown()
    }

    func test_lintXcodeVersion_doesntReturnIssues_theVersionsOfXcodeAreCompatible() async throws {
        // Given
        let configs = [
            Tuist.test(compatibleXcodeVersions: "4.3.2"),
            Tuist.test(compatibleXcodeVersions: .exact("4.3.2")),
            Tuist.test(compatibleXcodeVersions: .upToNextMajor("4.0")),
            Tuist.test(compatibleXcodeVersions: .upToNextMinor("4.3")),
            Tuist.test(compatibleXcodeVersions: ["1.0", "4.3.2"]),
        ]

        given(xcodeController)
            .selected()
            .willReturn(.test(infoPlist: .test(version: "4.3.2")))

        // When
        let got = try await configs.concurrentMap { try await self.subject.lintXcodeVersion(config: $0) }.flatMap { $0 }

        // Then
        XCTEmpty(got)
    }

    func test_lintXcodeVersion_returnsALintingIssue_when_theVersionsOfXcodeAreIncompatible() async throws {
        // Given
        let configs = [
            Tuist.test(compatibleXcodeVersions: "4.3.1"),
            Tuist.test(compatibleXcodeVersions: .exact("4.3.1")),
            Tuist.test(compatibleXcodeVersions: .upToNextMajor("3.0")),
            Tuist.test(compatibleXcodeVersions: .upToNextMajor("5.0")),
            Tuist.test(compatibleXcodeVersions: .upToNextMinor("4.2.0")),
            Tuist.test(compatibleXcodeVersions: .upToNextMinor("4.3.3")),
            Tuist.test(compatibleXcodeVersions: ["4.3", "4.3.3"]),
            Tuist.test(compatibleXcodeVersions: .list(["3.2.1"])),
        ]

        given(xcodeController)
            .selected()
            .willReturn(.test(infoPlist: .test(version: "4.3.2")))

        for config in configs {
            // When
            let got = try await subject.lintXcodeVersion(config: config)

            // Then
            let expectedMessage =
                "The selected Xcode version is 4.3.2, which is not compatible with this project's Xcode version requirement of \(config.compatibleXcodeVersions)."
            XCTAssertTrue(got.contains(LintingIssue(reason: expectedMessage, severity: .error)))
        }
    }

    func test_lintXcodeVersion_doesntReturnIssues_whenAllVersionsAreSupported() async throws {
        // Given
        let config = Tuist.test(compatibleXcodeVersions: .all)
        given(xcodeController)
            .selected()
            .willReturn(.test(infoPlist: .test(version: "4.3.2")))

        // When
        let got = try await subject.lintXcodeVersion(config: config)

        // Then
        XCTEmpty(got)
    }

    func test_lintXcodeVersion_throws_when_theSelectedXcodeCantBeObtained() async throws {
        // Given
        let config = Tuist.test(compatibleXcodeVersions: .list(["3.2.1"]))
        let error = NSError.test()
        given(xcodeController)
            .selected()
            .willThrow(error)

        // Then
        await XCTAssertThrowsSpecific(try await subject.lintXcodeVersion(config: config), error)
    }
}
