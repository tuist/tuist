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

struct TestCasesShowCommandServiceTests {
    private let getTestCaseService = MockGetTestCaseServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let subject: TestCasesShowCommandService

    init() {
        subject = TestCasesShowCommandService(
            getTestCaseService: getTestCaseService,
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

        await #expect(throws: TestCasesShowCommandServiceError.missingFullHandle, performing: {
            try await subject.run(
                project: nil,
                testCaseId: "case-1",
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

        let testCase = Components.Schemas.TestCaseRead(
            avg_duration: 1200,
            id: "case-1",
            last_duration: 1000,
            last_ran_at: 1_715_606_400,
            last_status: "success",
            module_name: "Module",
            name: "testExample",
            suite_name: "Suite",
            url: "https://tuist.dev/test-cases/1"
        )

        given(getTestCaseService).getTestCase(
            fullHandle: .value(fullHandle),
            testCaseId: .value("case-1"),
            serverURL: .value(serverURL)
        ).willReturn(testCase)

        try await subject.run(
            project: nil,
            testCaseId: "case-1",
            path: nil,
            json: true
        )

        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let testCaseJSON = String(data: try jsonEncoder.encode(testCase), encoding: .utf8)!
        #expect(ui().contains(testCaseJSON))
    }
}
