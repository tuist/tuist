import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Testing
import TuistCore
import TuistRootDirectoryLocator
import TuistSupport
@testable import TuistGenerator
@testable import TuistTesting

struct EnvironmentLinterTests {
    private var rootDirectoryLocator: MockRootDirectoryLocating!
    var subject: EnvironmentLinter!

    init() throws {
        rootDirectoryLocator = .init()
        subject = EnvironmentLinter(rootDirectoryLocator: rootDirectoryLocator)
    }

    @Test(.withMockedXcodeController) func lintXcodeVersion_doesntReturnIssues_theVersionsOfXcodeAreCompatible(
    ) async throws {
        // Given
        let configGeneratedProjectOptions = [
            TuistGeneratedProjectOptions.test(compatibleXcodeVersions: "4.3.2"),
            TuistGeneratedProjectOptions.test(compatibleXcodeVersions: .exact("4.3.2")),
            TuistGeneratedProjectOptions.test(compatibleXcodeVersions: .upToNextMajor("4.0")),
            TuistGeneratedProjectOptions.test(compatibleXcodeVersions: .upToNextMinor("4.3")),
            TuistGeneratedProjectOptions.test(compatibleXcodeVersions: ["1.0", "4.3.2"]),
        ]

        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selected()
            .willReturn(.test(infoPlist: .test(version: "4.3.2")))

        // When
        let got = try await configGeneratedProjectOptions
            .concurrentMap { try await subject.lintXcodeVersion(configGeneratedProjectOptions: $0) }.flatMap { $0 }

        // Then
        #expect(got.isEmpty == true)
    }

    @Test(.withMockedXcodeController) func lintXcodeVersion_returnsALintingIssue_when_theVersionsOfXcodeAreIncompatible(
    ) async throws {
        // Given
        let configGeneratedProjectOptions = [
            TuistGeneratedProjectOptions.test(compatibleXcodeVersions: "4.3.1"),
            TuistGeneratedProjectOptions.test(compatibleXcodeVersions: .exact("4.3.1")),
            TuistGeneratedProjectOptions.test(compatibleXcodeVersions: .upToNextMajor("3.0")),
            TuistGeneratedProjectOptions.test(compatibleXcodeVersions: .upToNextMajor("5.0")),
            TuistGeneratedProjectOptions.test(compatibleXcodeVersions: .upToNextMinor("4.2.0")),
            TuistGeneratedProjectOptions.test(compatibleXcodeVersions: .upToNextMinor("4.3.3")),
            TuistGeneratedProjectOptions.test(compatibleXcodeVersions: ["4.3", "4.3.3"]),
            TuistGeneratedProjectOptions.test(compatibleXcodeVersions: .list(["3.2.1"])),
        ]

        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selected()
            .willReturn(.test(infoPlist: .test(version: "4.3.2")))

        for options in configGeneratedProjectOptions {
            // When
            let got = try await subject.lintXcodeVersion(configGeneratedProjectOptions: options)

            // Then
            let expectedMessage =
                "The selected Xcode version is 4.3.2, which is not compatible with this project's Xcode version requirement of \(options.compatibleXcodeVersions)."
            #expect(got.contains(LintingIssue(reason: expectedMessage, severity: .error)) == true)
        }
    }

    @Test(.withMockedXcodeController) func lintXcodeVersion_doesntReturnIssues_whenAllVersionsAreSupported() async throws {
        // Given
        let configGeneratedProjectOptions = TuistGeneratedProjectOptions.test(compatibleXcodeVersions: .all)
        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selected()
            .willReturn(.test(infoPlist: .test(version: "4.3.2")))

        // When
        let got = try await subject.lintXcodeVersion(configGeneratedProjectOptions: configGeneratedProjectOptions)

        // Then
        #expect(got.isEmpty == true)
    }

    @Test(.withMockedXcodeController) func lintXcodeVersion_throws_when_theSelectedXcodeCantBeObtained() async throws {
        // Given
        let configGeneratedProjectOptions = TuistGeneratedProjectOptions.test(compatibleXcodeVersions: .list(["3.2.1"]))
        let error = NSError.test()
        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selected()
            .willThrow(error)

        // Then
        await #expect(throws: error) {
            try await subject.lintXcodeVersion(configGeneratedProjectOptions: configGeneratedProjectOptions)
        }
    }
}
