import FileSystem
import FileSystemTesting
import Foundation
import Testing
import TuistAcceptanceTesting
import TuistCore
import TuistEnvironment
import TuistLoggerTesting
import TuistLogging
import TuistNooraTesting
import TuistServer
import TuistSupport
import TuistTesting
@testable import TuistInspectCommand
@testable import TuistKit

struct InspectAcceptanceTests {
    /// Runs `tuist xcodebuild build` against canary and polls the server until the resulting
    /// build run reaches a terminal status. `xcodebuild build` already exercises the same
    /// upload path that `tuist inspect build` uses (via `UploadBuildRunService`), so this
    /// test catches regressions in either entry point.
    ///
    /// Disabled for now: processing on canary takes >30s in CI, which we don't want to
    /// paper over with longer timeouts. Re-enable once canary's build processor returns
    /// terminal status quickly enough that the polling window can stay tight.
    @Test(
        .disabled("Canary build processor latency exceeds the polling window — see PR #10472."),
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("xcode_project_with_inspect_build")
    )
    func build() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fullHandle = try #require(TuistTest.fixtureFullHandle)
        let serverURL = try #require(
            URL(string: Environment.current.variables["TUIST_URL"] ?? "https://canary.tuist.dev")
        )

        try await TuistTest.run(
            XcodeBuildBuildCommand.self,
            [
                "-scheme", "App",
                "-destination", "platform=macOS,arch=arm64",
                "-project", fixtureDirectory.appending(component: "App.xcodeproj").pathString,
                "-derivedDataPath", temporaryDirectory.pathString,
                "CODE_SIGN_IDENTITY=",
                "CODE_SIGNING_REQUIRED=NO",
                "CODE_SIGNING_ALLOWED=NO",
            ]
        )

        let buildId = try #require(
            await RunMetadataStorage.current.buildRunId,
            "XcodeBuildBuildCommand did not record a buildRunId"
        )
        Logger.current.warning("Polling build \(buildId) on \(serverURL.absoluteString) for \(fullHandle)")

        let build = try await Self.pollUntilProcessed(
            timeout: .seconds(30),
            interval: .seconds(2),
            label: "build \(buildId)",
            isTerminal: { $0.status != .processing }
        ) {
            try await GetBuildService().getBuild(
                fullHandle: fullHandle,
                buildId: buildId,
                serverURL: serverURL
            )
        }

        // The fixture builds successfully — `failed_processing` would mean the upload
        // made it to the server but the worker couldn't parse the activity log, which is
        // the regression shape we want this test to catch.
        #expect(build.status == .success, "Expected build status .success but got \(build.status.rawValue)")
    }

    /// Runs `tuist xcodebuild test` against canary and polls the server until the resulting
    /// test run reaches a terminal status. `xcodebuild test` already exercises the same
    /// xcresult upload path that `tuist inspect test` uses (via
    /// `AnalyticsArtifactUploadService.uploadResultBundle`), so this test catches
    /// regressions in either entry point.
    ///
    /// Disabled for now: processing on canary takes >30s in CI, which we don't want to
    /// paper over with longer timeouts. Re-enable once canary's xcresult processor returns
    /// terminal status quickly enough that the polling window can stay tight.
    @Test(
        .disabled("Canary xcresult processor latency exceeds the polling window — see PR #10472."),
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("xcode_project_with_inspect_build")
    )
    func test() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fullHandle = try #require(TuistTest.fixtureFullHandle)
        let serverURL = try #require(
            URL(string: Environment.current.variables["TUIST_URL"] ?? "https://canary.tuist.dev")
        )

        try await TuistTest.run(
            XcodeBuildTestCommand.self,
            [
                "-scheme", "App",
                "-destination", "platform=macOS,arch=arm64",
                "-project", fixtureDirectory.appending(component: "App.xcodeproj").pathString,
                "-derivedDataPath", temporaryDirectory.pathString,
                "CODE_SIGN_IDENTITY=",
                "CODE_SIGNING_REQUIRED=NO",
                "CODE_SIGNING_ALLOWED=NO",
            ]
        )

        let testRunId = try #require(
            await RunMetadataStorage.current.testRunId,
            "XcodeBuildTestCommand did not record a testRunId"
        )
        Logger.current.warning("Polling test run \(testRunId) on \(serverURL.absoluteString) for \(fullHandle)")

        let testRun = try await Self.pollUntilProcessed(
            timeout: .seconds(30),
            interval: .seconds(2),
            label: "test run \(testRunId)",
            isTerminal: { $0.status != .in_progress && $0.status != .processing }
        ) {
            try await GetTestRunService().getTestRun(
                fullHandle: fullHandle,
                testRunId: testRunId,
                serverURL: serverURL
            )
        }

        // The fixture's tests pass — `failed_processing` would mean the upload made it to
        // the server but the worker couldn't parse the xcresult, which is the regression
        // shape we want this test to catch.
        #expect(testRun.status == .success, "Expected test run status .success but got \(testRun.status.rawValue)")
    }

    /// Polls `operation` until `isTerminal` returns true or the deadline is reached.
    /// Transient errors (network blips, 5xx) are treated as "not yet ready" so the test
    /// stays robust on the canary deploy gate.
    private static func pollUntilProcessed<Value>(
        timeout: Duration,
        interval: Duration,
        label: String,
        isTerminal: @Sendable (Value) -> Bool,
        operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var lastError: (any Error)?
        while clock.now < deadline {
            do {
                let value = try await operation()
                if isTerminal(value) {
                    return value
                }
            } catch {
                lastError = error
                Logger.current.warning("Polling \(label): \(error.localizedDescription)")
            }
            try await Task.sleep(for: interval)
        }
        if let lastError {
            Issue.record("Timed out after \(timeout) waiting for \(label) to be processed; last error: \(lastError)")
        } else {
            Issue.record("Timed out after \(timeout) waiting for \(label) to be processed")
        }
        return try await operation()
    }

    @Test(
        .disabled(),
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("xcode_project_with_inspect_build")
    )
    func bundle() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let arguments = [
            "-scheme", "App",
            "-destination", "generic/platform=iOS Simulator",
            "-project", fixtureDirectory.appending(component: "App.xcodeproj").pathString,
            "-resultBundlePath", fixtureDirectory.appending(component: "result.xcresult").pathString,
            "-derivedDataPath", temporaryDirectory.pathString,
        ]

        // When: I build the app
        try await TuistTest.run(
            XcodeBuildBuildCommand.self,
            arguments
        )

        // When: I inspect the bundle
        try await TuistTest.run(
            InspectBundleCommand.self,
            [
                "--path",
                fixtureDirectory.pathString,
                temporaryDirectory.appending(components: "Build", "Products", "Debug-iphonesimulator", "App.app").pathString,
            ]
        )

        // Then
        #expect(ui().contains("""
        ✔︎ Bundle analyzed
        """) == true)
    }
}

struct LintAcceptanceTests {
    @Test(.disabled(), .withFixture("generated_ios_app_with_headers"), .withMockedDependencies())
    func ios_app_with_headers() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(InspectImplicitImportsCommand.self, ["--path", fixtureDirectory.pathString])
        TuistTest.expectLogs(
            "We did not find any dependency issues in your project (checked: implicit).",
            at: .info,
            <=
        )
    }

    @Test(.disabled(), .withFixture("generated_ios_app_with_implicit_dependencies"), .withMockedDependencies())
    func ios_app_with_implicit_dependencies() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let appDependencies: Set = [
            "ClassModule",
            "EnumModule",
            "FuncModule",
            "LetModule",
            "ProtocolModule",
            "StructModule",
            "TypeAliasModule",
            "VarModule",
        ]
        await #expect(throws: InspectImportsServiceError.issuesFound(implicit: [
            .init(target: "App", dependencies: appDependencies),
            .init(target: "FrameworkA", dependencies: ["FrameworkB"]),
        ])) {
            try await TuistTest.run(InspectImplicitImportsCommand.self, ["--path", fixtureDirectory.pathString])
        }
    }

    @Test(.disabled(), .withFixture("generated_framework_with_macros_and_tests"), .withMockedDependencies())
    func framework_with_macros_redundant_imports() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(InspectRedundantImportsCommand.self, ["--path", fixtureDirectory.pathString])
        TuistTest.expectLogs(
            "We did not find any dependency issues in your project (checked: redundant).",
            at: .info,
            <=
        )
    }
}
