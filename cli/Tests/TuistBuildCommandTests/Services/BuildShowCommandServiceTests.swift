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

struct BuildShowCommandServiceTests {
    private let getBuildService = MockGetBuildServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let subject: BuildShowCommandService!

    init() {
        subject = BuildShowCommandService(
            getBuildService: getBuildService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )
    }

    @Test(.withMockedEnvironment()) func run_when_full_handle_is_not_passed_and_absent_in_config() async throws {
        // Given
        let tuist = Tuist.test(fullHandle: nil)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)

        // When
        await #expect(throws: BuildShowCommandServiceError.missingFullHandle, performing: {
            try await subject.run(
                fullHandle: nil,
                buildId: "build-123",
                path: nil,
                json: false
            )
        })
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_when_full_handle_is_present_in_config_and_not_json() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let buildId = UUID().uuidString
        let tuist = Tuist.test(fullHandle: fullHandle)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        let build = testBuild()
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        given(getBuildService).getBuild(
            fullHandle: .value(fullHandle),
            buildId: .value(buildId),
            serverURL: .value(serverURL)
        ).willReturn(build)

        // When
        try await subject.run(
            fullHandle: nil,
            buildId: buildId,
            path: nil,
            json: false
        )

        // Then
        #expect(ui().contains(subject.formatBuildInfo(build)))
    }

    @Test(
        .withMockedEnvironment(arguments: ["--json"]),
        .withMockedNoora
    ) func run_when_full_handle_is_present_in_config_and_json() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let buildId = UUID().uuidString
        let tuist = Tuist.test(fullHandle: fullHandle)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        let build = testBuild()
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        given(getBuildService).getBuild(
            fullHandle: .value(fullHandle),
            buildId: .value(buildId),
            serverURL: .value(serverURL)
        ).willReturn(build)

        // When
        try await subject.run(
            fullHandle: nil,
            buildId: buildId,
            path: nil,
            json: true
        )

        // Then
        let jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let buildJSON = String(data: try jsonEncoder.encode(build), encoding: .utf8)!
        #expect(ui().contains(buildJSON))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_when_full_handle_is_passed_and_absent_in_config() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let buildId = UUID().uuidString
        let tuist = Tuist.test(fullHandle: nil)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        let build = testBuild()
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        given(getBuildService).getBuild(
            fullHandle: .value(fullHandle),
            buildId: .value(buildId),
            serverURL: .value(serverURL)
        ).willReturn(build)

        // When
        try await subject.run(
            fullHandle: fullHandle,
            buildId: buildId,
            path: nil,
            json: false
        )

        // Then
        #expect(ui().contains(subject.formatBuildInfo(build)))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_when_full_handle_is_passed_takes_precedence_over_config() async throws {
        // Given
        let configFullHandle = "\(UUID().uuidString)/\(UUID().uuidString)-config"
        let optionFullHandle = "\(UUID().uuidString)/\(UUID().uuidString)-option"
        let buildId = UUID().uuidString
        let tuist = Tuist.test(fullHandle: configFullHandle)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        let build = testBuild()
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)

        // The full handle passed through CLI args takes precedence
        given(getBuildService).getBuild(
            fullHandle: .value(optionFullHandle),
            buildId: .value(buildId),
            serverURL: .value(serverURL)
        ).willReturn(build)

        // When
        try await subject.run(
            fullHandle: optionFullHandle,
            buildId: buildId,
            path: nil,
            json: false
        )

        // Then
        #expect(ui().contains(subject.formatBuildInfo(build)))
    }

    private func testBuild() -> Build {
        return Build(
            cacheable_task_local_hits_count: 3,
            cacheable_task_remote_hits_count: 5,
            cacheable_tasks_count: 10,
            category: .clean,
            configuration: "Debug",
            duration: 5000,
            git_branch: "main",
            git_commit_sha: "abc123",
            git_ref: "refs/heads/main",
            id: UUID().uuidString,
            inserted_at: Date(),
            is_ci: false,
            macos_version: "14.0",
            model_identifier: "Mac14,2",
            scheme: "MyApp",
            status: .success,
            url: "https://tuist.dev/builds/\(UUID().uuidString)",
            xcode_version: "15.0"
        )
    }
}
