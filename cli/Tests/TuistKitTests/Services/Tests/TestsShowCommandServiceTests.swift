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

struct TestsShowCommandServiceTests {
    private let getTestService = MockGetTestServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let subject: TestsShowCommandService

    init() {
        subject = TestsShowCommandService(
            getTestService: getTestService,
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

        await #expect(throws: TestsShowCommandServiceError.missingFullHandle, performing: {
            try await subject.run(
                project: nil,
                testId: "test-1",
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

        given(getTestService).getTest(
            fullHandle: .value(fullHandle),
            testId: .value("test-1"),
            serverURL: .value(serverURL)
        ).willReturn(testRun)

        try await subject.run(
            project: nil,
            testId: "test-1",
            path: nil,
            json: true
        )

        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let testJSON = String(data: try jsonEncoder.encode(testRun), encoding: .utf8)!
        #expect(ui().contains(testJSON))
    }
}
