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

struct BuildsListCommandServiceTests {
    private let listBuildsService = MockListBuildsServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let subject: BuildsListCommandService

    init() {
        subject = BuildsListCommandService(
            listBuildsService: listBuildsService,
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

        await #expect(throws: BuildsListCommandServiceError.missingFullHandle, performing: {
            try await subject.run(
                project: nil,
                path: nil,
                status: nil,
                category: nil,
                scheme: nil,
                configuration: nil,
                gitBranch: nil,
                gitCommitSHA: nil,
                gitRef: nil,
                page: nil,
                perPage: nil,
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

        let response = Operations.listBuilds.Output.Ok.Body.jsonPayload(builds: [build])

        given(listBuildsService).listBuilds(
            fullHandle: .value(fullHandle),
            status: .value(nil),
            category: .value(nil),
            scheme: .value(nil),
            configuration: .value(nil),
            gitBranch: .value(nil),
            gitCommitSHA: .value(nil),
            gitRef: .value(nil),
            page: .value(nil),
            pageSize: .value(50),
            serverURL: .value(serverURL)
        ).willReturn(response)

        try await subject.run(
            project: nil,
            path: nil,
            status: nil,
            category: nil,
            scheme: nil,
            configuration: nil,
            gitBranch: nil,
            gitCommitSHA: nil,
            gitRef: nil,
            page: nil,
            perPage: nil,
            json: true
        )

        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let buildsJSON = String(data: try jsonEncoder.encode(response), encoding: .utf8)!
        #expect(ui().contains(buildsJSON))
    }
}
