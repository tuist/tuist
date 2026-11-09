import Foundation
import Mockable
import Testing
import TuistConfig
import TuistConfigLoader
import TuistEnvironment
import TuistEnvironmentTesting
import TuistNooraTesting
import TuistServer

@testable import TuistBuildCommand

struct BuildGradleFailureListCommandServiceTests {
    private let listGradleBuildFailuresService = MockListGradleBuildFailuresServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let subject: BuildGradleFailureListCommandService

    init() {
        subject = BuildGradleFailureListCommandService(
            listGradleBuildFailuresService: listGradleBuildFailuresService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )
    }

    @Test(.withMockedEnvironment()) func run_when_full_handle_is_missing() async throws {
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(Tuist.test(fullHandle: nil))

        await #expect(throws: BuildGradleFailureListCommandServiceError.missingFullHandle) {
            try await subject.run(fullHandle: nil, buildId: "build", path: nil, json: false)
        }
    }

    @Test(.withMockedEnvironment(), .withMockedNoora) func run_prints_each_failure_with_its_message() async throws {
        let failures = try await givenFailures([
            failure(
                category: "configuration",
                title: "project",
                target: ":app",
                message: "A problem occurred evaluating project ':app'.\n> boom"
            ),
            failure(
                category: "JavaCompile",
                title: ":app:compileJava",
                target: ":app:compileJava",
                message: "Execution failed for task ':app:compileJava'.",
                truncated: true
            ),
            failure(category: "Test", title: ":app:test", target: ":app:test", message: nil),
        ])

        try await subject.run(fullHandle: nil, buildId: "build", path: nil, json: false)

        let output = ui()
        #expect(output.contains("Configuration (project) :app\nA problem occurred evaluating project ':app'.\n> boom"))
        #expect(output.contains(":app:compileJava\nExecution failed for task ':app:compileJava'.\n(message truncated)"))
        #expect(output.contains(":app:test\nNo failure message was reported."))
        #expect(failures.count == 3)
    }

    @Test(.withMockedEnvironment(arguments: ["--json"]), .withMockedNoora) func run_with_json() async throws {
        let failures = try await givenFailures([
            failure(category: "JavaCompile", title: ":app:compileJava", target: ":app:compileJava", message: "failed"),
        ])

        try await subject.run(fullHandle: nil, buildId: "build", path: nil, json: true)

        let output = ui()
        #expect(output.contains("\"message\" : \"failed\""))
        #expect(output.contains("\"message_truncated\" : false"))
        #expect(output.contains("\"id\" : \"\(failures[0].id)\""))
    }

    @Test(.withMockedEnvironment(), .withMockedNoora) func run_without_failures() async throws {
        _ = try await givenFailures([])

        try await subject.run(fullHandle: nil, buildId: "build", path: nil, json: false)

        #expect(ui().contains("No failed tasks or configuration steps were recorded for Gradle build build."))
    }

    private func givenFailures(_ failures: [ServerGradleBuildFailure]) async throws -> [ServerGradleBuildFailure] {
        let fullHandle = "account/project"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let serverURL = URL(string: "https://tuist.dev")!
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        given(listGradleBuildFailuresService).listGradleBuildFailures(
            fullHandle: .value(fullHandle),
            serverURL: .value(serverURL),
            buildId: .value("build")
        ).willReturn(failures)
        return failures
    }

    private func failure(
        category: String,
        title: String,
        target: String,
        message: String?,
        truncated: Bool = false
    ) -> ServerGradleBuildFailure {
        ServerGradleBuildFailure(
            id: "\(category == "configuration" ? "configuration" : "task"):\(UUID().uuidString)",
            title: title,
            project: ":",
            target: target,
            category: category,
            startMs: 10,
            durationMs: 5,
            message: message,
            messageTruncated: truncated
        )
    }
}
