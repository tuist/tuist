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

struct CacheRunsListCommandServiceTests {
    private let listCacheRunsService = MockListCacheRunsServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let subject: CacheRunsListCommandService

    init() {
        subject = CacheRunsListCommandService(
            listCacheRunsService: listCacheRunsService,
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

        await #expect(throws: CacheRunsListCommandServiceError.missingFullHandle, performing: {
            try await subject.run(
                project: nil,
                path: nil,
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

        let run = Components.Schemas.Run(
            cacheable_targets: [],
            command_arguments: [],
            duration: 1200,
            git_branch: "main",
            git_commit_sha: "abc",
            git_ref: "refs/heads/main",
            id: 123,
            local_cache_target_hits: [],
            local_test_target_hits: [],
            macos_version: "14.0",
            name: "cache",
            preview_id: nil,
            ran_at: 1_715_606_400,
            ran_by: nil,
            remote_cache_target_hits: [],
            remote_test_target_hits: [],
            status: "success",
            subcommand: "",
            swift_version: "5.9",
            test_targets: [],
            tuist_version: "4.0.0",
            url: "https://tuist.dev/run/123"
        )

        let response = Operations.listCacheRuns.Output.Ok.Body.jsonPayload(runs: [run])

        given(listCacheRunsService).listCacheRuns(
            fullHandle: .value(fullHandle),
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
            gitBranch: nil,
            gitCommitSHA: nil,
            gitRef: nil,
            page: nil,
            perPage: nil,
            json: true
        )

        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let runsJSON = String(data: try jsonEncoder.encode(response), encoding: .utf8)!
        #expect(ui().contains(runsJSON))
    }
}
