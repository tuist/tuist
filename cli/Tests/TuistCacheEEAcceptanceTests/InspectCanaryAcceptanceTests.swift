import Command
import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistAcceptanceTesting
import TuistCore
import TuistEnvironment
import TuistEnvironmentTesting
import TuistLoggerTesting
import TuistNooraTesting
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistInspectCommand
@testable import TuistKit

/// Acceptance tests that exercise `tuist inspect test` and `tuist inspect build` against a
/// real canary deployment. They upload an xcresult / activity log and then poll the server
/// until processing finishes — catching regressions like the one shipped in
/// https://github.com/tuist/tuist/pull/10460, where the AppleArchive payload was missing the
/// `.xcresult` wrapper and the server's `find_xcresult` could never locate the bundle.
struct InspectCanaryAcceptanceTests {
    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("xcode_project_with_inspect_build")
    ) func inspect_test_processes_xcresult_through_canary() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fullHandle = try #require(TuistTest.fixtureFullHandle)
        let serverURL = try #require(
            URL(string: Environment.current.variables["TUIST_URL"] ?? "https://canary.tuist.dev")
        )

        let commandRunner = CommandRunner()
        try await commandRunner.run(
            arguments: [
                "/usr/bin/xcrun",
                "xcodebuild",
                "clean",
                "test",
                "-scheme", "App",
                "-destination", "platform=iOS Simulator,name=iPhone 17",
                "-project", fixtureDirectory.appending(component: "App.xcodeproj").pathString,
                "-derivedDataPath", temporaryDirectory.pathString,
            ]
        ).pipedStream().awaitCompletion()

        try await TuistTest.run(
            InspectTestCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", temporaryDirectory.pathString]
        )

        let testRunId = try #require(
            Self.firstMatch(in: ui(), pattern: #"/tests/test-runs/([0-9a-fA-F-]+)"#),
            "Could not extract a test run id from the inspect output"
        )

        let testRun = try await Self.pollUntilDecodable(
            timeout: .seconds(180),
            interval: .seconds(3),
            label: "test run \(testRunId)"
        ) {
            try await GetTestRunService().getTestRun(
                fullHandle: fullHandle,
                testRunId: testRunId,
                serverURL: serverURL
            )
        }

        // The fixture's tests pass — anything other than `.success` means processing
        // either bailed out (`failed_processing`, which the OpenAPI client can't decode
        // and would have looped until timeout) or the parser flagged failures.
        #expect(testRun.status == .success)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("xcode_project_with_inspect_build")
    ) func inspect_build_processes_activity_log_through_canary() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fullHandle = try #require(TuistTest.fixtureFullHandle)
        let serverURL = try #require(
            URL(string: Environment.current.variables["TUIST_URL"] ?? "https://canary.tuist.dev")
        )

        let commandRunner = CommandRunner()
        try await commandRunner.run(
            arguments: [
                "/usr/bin/xcrun",
                "xcodebuild",
                "clean",
                "build",
                "-scheme", "App",
                "-destination", "generic/platform=iOS Simulator",
                "-project", fixtureDirectory.appending(component: "App.xcodeproj").pathString,
                "-derivedDataPath", temporaryDirectory.pathString,
            ]
        ).pipedStream().awaitCompletion()

        try await TuistTest.run(
            InspectBuildCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", temporaryDirectory.pathString]
        )

        let buildId = try #require(
            Self.firstMatch(in: ui(), pattern: #"/builds/build-runs/([0-9a-zA-Z\-]+)"#),
            "Could not extract a build id from the inspect output"
        )

        let build = try await Self.pollUntilDecodable(
            timeout: .seconds(180),
            interval: .seconds(3),
            label: "build \(buildId)"
        ) {
            try await GetBuildService().getBuild(
                fullHandle: fullHandle,
                buildId: buildId,
                serverURL: serverURL
            )
        }

        #expect(build.status == .success)
    }

    /// Polls `operation` until it returns successfully or the deadline is reached.
    ///
    /// The server reports `processing` / `failed_processing` for builds and test runs that
    /// haven't been parsed yet, but the OpenAPI schemas for `getTestRun` and `getBuild` only
    /// declare the terminal statuses. Decoding therefore throws while the run is still
    /// processing, which is exactly the signal we want — once decoding succeeds the run has
    /// reached a terminal state. Any other error (network blip, transient 5xx) is also
    /// treated as "not yet ready" so the test stays robust on the canary deploy gate.
    private static func pollUntilDecodable<Value>(
        timeout: Duration,
        interval: Duration,
        label: String,
        operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if let value = try? await operation() {
                return value
            }
            try await Task.sleep(for: interval)
        }
        Issue.record("Timed out after \(timeout) waiting for \(label) to be processed")
        return try await operation()
    }

    private static func firstMatch(in input: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(input.startIndex ..< input.endIndex, in: input)
        guard
            let match = regex.firstMatch(in: input, range: range),
            match.numberOfRanges > 1,
            let captureRange = Range(match.range(at: 1), in: input)
        else { return nil }
        return String(input[captureRange])
    }
}
