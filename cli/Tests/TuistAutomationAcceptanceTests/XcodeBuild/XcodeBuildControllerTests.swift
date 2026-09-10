import Foundation
import Path
import Testing
import TuistCore
import TuistLoggerTesting
import TuistLogging
import TuistSupport

@testable import TuistAutomation
@testable import TuistTesting

struct XcodeBuildControllerTests {
    @Test func showBuildSettings() async throws {
        // Given
        let target = XcodeBuildTarget.project(
            SwiftTestingHelper.fixturePath(path: try RelativePath(validating: "Frameworks/Frameworks.xcodeproj"))
        )
        let subject = XcodeBuildController()

        // When
        let got = try await subject.showBuildSettings(target, scheme: "iOS", configuration: "Debug", derivedDataPath: nil)

        // Then
        #expect(got.count == 1)
        let buildSettings = try #require(got["iOS"])
        #expect(buildSettings.productName == "iOS")
    }

    @Test func version() async throws {
        // When
        let subject = XcodeBuildController()
        let version = try await subject.version()

        // Then
        #expect(version != nil)
    }

    @Test(.withMockedLogger()) func run_keeps_unformattable_output_in_the_session_log() async throws {
        // Given
        let projectPath = SwiftTestingHelper.fixturePath(
            path: try RelativePath(validating: "Frameworks/Frameworks.xcodeproj")
        )
        let subject = XcodeBuildController()
        Logger.testingLogHandler.logLevel = .debug

        // When
        try await subject.run(
            arguments: [
                "build",
                "-project", projectPath.pathString,
                "-scheme", "iOS",
                "-destination", "generic/platform=iOS Simulator",
                "CODE_SIGNING_ALLOWED=NO",
                "CODE_SIGNING_REQUIRED=NO",
                "CODE_SIGN_IDENTITY=",
            ]
        )

        // Then
        // xcodebuild opens every invocation with this header and xcbeautify has no rule for it, so
        // it stands in for the script phase output that used to be discarded.
        let logs = Logger.testingLogHandler.collected
        #expect(logs[.debug, default: []].contains { $0.hasPrefix("Command line invocation:") })
        #expect(!logs[.info, default: []].contains { $0.hasPrefix("Command line invocation:") })
    }
}
