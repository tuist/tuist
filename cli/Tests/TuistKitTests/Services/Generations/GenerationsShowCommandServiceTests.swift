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

struct GenerationsShowCommandServiceTests {
    private let getGenerationService = MockGetGenerationServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let subject: GenerationsShowCommandService

    init() {
        subject = GenerationsShowCommandService(
            getGenerationService: getGenerationService,
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

        await #expect(throws: GenerationsShowCommandServiceError.missingFullHandle, performing: {
            try await subject.run(
                project: nil,
                runId: "123",
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
            name: "generate",
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

        given(getGenerationService).getGeneration(
            fullHandle: .value(fullHandle),
            runId: .value("123"),
            serverURL: .value(serverURL)
        ).willReturn(run)

        try await subject.run(
            project: nil,
            runId: "123",
            path: nil,
            json: true
        )

        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let runJSON = String(data: try jsonEncoder.encode(run), encoding: .utf8)!
        #expect(ui().contains(runJSON))
    }
}
