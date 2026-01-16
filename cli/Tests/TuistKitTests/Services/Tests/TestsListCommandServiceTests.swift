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

struct TestsListCommandServiceTests {
    private let listTestsService = MockListTestsServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let subject: TestsListCommandService

    init() {
        subject = TestsListCommandService(
            listTestsService: listTestsService,
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

        await #expect(throws: TestsListCommandServiceError.missingFullHandle, performing: {
            try await subject.run(
                project: nil,
                path: nil,
                status: nil,
                scheme: nil,
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

        let testRun = Components.Schemas.TestRunRead(
            build_run_id: "build-1",
            duration: 1200,
            git_branch: "main",
            git_commit_sha: "abc",
            git_ref: "refs/heads/main",
            id: "test-1",
            is_ci: false,
            macos_version: "14.0",
            model_identifier: "Mac15,6",
            ran_at: 1_715_606_400,
            ran_by: nil,
            scheme: "AppTests",
            status: "success",
            url: "https://tuist.dev/test/1",
            xcode_version: "15.0"
        )

        let response = Operations.listTests.Output.Ok.Body.jsonPayload(tests: [testRun])

        given(listTestsService).listTests(
            fullHandle: .value(fullHandle),
            status: .value(nil),
            scheme: .value(nil),
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
            scheme: nil,
            gitBranch: nil,
            gitCommitSHA: nil,
            gitRef: nil,
            page: nil,
            perPage: nil,
            json: true
        )

        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let testsJSON = String(data: try jsonEncoder.encode(response), encoding: .utf8)!
        #expect(ui().contains(testsJSON))
    }
}
