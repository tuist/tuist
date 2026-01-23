import FileSystemTesting
import Foundation
import Mockable
import Testing
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistKit

struct BuildsShowCommandServiceTests {
    private let getBuildService = MockGetBuildServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let subject: BuildsShowCommandService

    init() {
        subject = BuildsShowCommandService(
            getBuildService: getBuildService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )
    }

    @Test(.withMockedEnvironment()) func run_when_full_handle_is_missing() async throws {
        let tuist = Tuist.test(fullHandle: nil)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)

        await #expect(throws: BuildsShowCommandServiceError.missingFullHandle, performing: {
            try await subject.run(
                project: nil,
                buildId: "build-1",
                path: nil,
                json: false
            )
        })
    }

    @Test(
        .withMockedEnvironment(arguments: ["--json"]),
        .withMockedNoora
    ) func run_when_json_enabled() async throws {
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)

        let build = Components.Schemas.BuildRunRead(
            cacheable_task_local_hits_count: 1,
            cacheable_task_remote_hits_count: 2,
            cacheable_tasks_count: 3,
            category: "incremental",
            configuration: "Debug",
            duration: 1200,
            git_branch: "main",
            git_commit_sha: "abc",
            git_ref: "refs/heads/main",
            id: "build-1",
            is_ci: false,
            macos_version: "14.0",
            model_identifier: "Mac15,6",
            ran_at: 1_715_606_400,
            ran_by: nil,
            scheme: "App",
            status: "success",
            url: "https://tuist.dev/build/1",
            xcode_version: "15.0"
        )

        given(getBuildService).getBuild(
            fullHandle: .value(fullHandle),
            buildId: .value("build-1"),
            serverURL: .value(serverURL)
        ).willReturn(build)

        try await subject.run(
            project: nil,
            buildId: "build-1",
            path: nil,
            json: true
        )

        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let buildJSON = String(data: try jsonEncoder.encode(build), encoding: .utf8)!
        #expect(ui().contains(buildJSON))
    }
}
