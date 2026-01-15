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

struct TestCasesListCommandServiceTests {
    private let listTestCasesService = MockListTestCasesServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let subject: TestCasesListCommandService

    init() {
        subject = TestCasesListCommandService(
            listTestCasesService: listTestCasesService,
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

        await #expect(throws: TestCasesListCommandServiceError.missingFullHandle, performing: {
            try await subject.run(
                project: nil,
                path: nil,
                name: nil,
                moduleName: nil,
                suiteName: nil,
                status: nil,
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

        let response = Operations.listTestCases.Output.Ok.Body.jsonPayload(test_cases: [testCase])

        given(listTestCasesService).listTestCases(
            fullHandle: .value(fullHandle),
            name: .value(nil),
            moduleName: .value(nil),
            suiteName: .value(nil),
            status: .value(nil),
            page: .value(nil),
            pageSize: .value(50),
            serverURL: .value(serverURL)
        ).willReturn(response)

        try await subject.run(
            project: nil,
            path: nil,
            name: nil,
            moduleName: nil,
            suiteName: nil,
            status: nil,
            json: true
        )

        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let testCasesJSON = String(data: try jsonEncoder.encode(response), encoding: .utf8)!
        #expect(ui().contains(testCasesJSON))
    }
}
