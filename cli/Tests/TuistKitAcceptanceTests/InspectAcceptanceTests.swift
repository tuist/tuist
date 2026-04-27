import FileSystem
import FileSystemTesting
import Foundation
import Testing
import TuistAcceptanceTesting
import TuistCore
import TuistEnvironment
import TuistLoggerTesting
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
    @Test(
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
                "-destination", "generic/platform=iOS Simulator",
                "-project", fixtureDirectory.appending(component: "App.xcodeproj").pathString,
                "-derivedDataPath", temporaryDirectory.pathString,
            ]
        )

        let buildId = try #require(
            await RunMetadataStorage.current.buildRunId,
            "XcodeBuildBuildCommand did not record a buildRunId"
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

    /// Runs `tuist xcodebuild test` against canary and polls the server until the resulting
    /// test run reaches a terminal status. `xcodebuild test` already exercises the same
    /// xcresult upload path that `tuist inspect test` uses (via
    /// `AnalyticsArtifactUploadService.uploadResultBundle`) — that's the path broken by
    /// https://github.com/tuist/tuist/pull/10460, where the AppleArchive payload was missing
    /// the `.xcresult` wrapper and the server's `find_xcresult` could never locate the
    /// bundle.
    @Test(
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
                "-destination", "platform=iOS Simulator,name=iPhone 17",
                "-project", fixtureDirectory.appending(component: "App.xcodeproj").pathString,
                "-derivedDataPath", temporaryDirectory.pathString,
            ]
        )

        let testRunId = try #require(
            await RunMetadataStorage.current.testRunId,
            "XcodeBuildTestCommand did not record a testRunId"
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

        // The fixture's tests pass — anything other than `.success` means processing either
        // bailed out (`failed_processing`, which the OpenAPI client can't decode and would
        // have looped until timeout) or the parser flagged failures.
        #expect(testRun.status == .success)
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
