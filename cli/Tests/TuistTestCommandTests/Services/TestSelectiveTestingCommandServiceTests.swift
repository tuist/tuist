import Foundation
import Mockable
import Testing
import TuistConfig
import TuistConfigLoader
import TuistEnvironment
import TuistEnvironmentTesting
import TuistNooraTesting
import TuistServer

@testable import TuistTestCommand

struct TestSelectiveTestingCommandServiceTests {
    private let selectiveTestingService = MockSelectiveTestingServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let serverURL = URL(string: "https://tuist.example.com")!

    private func givenProject(fullHandle: String? = "acme/app") async throws {
        let config = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(config)
        given(serverEnvironmentService).url(configServerURL: .any).willReturn(serverURL)
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private static let pagination = """
    {"current_page":1,"has_next_page":false,"has_previous_page":false,"page_size":20,"total_count":2,"total_pages":1}
    """

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func listsTheTestsTheSelectionDecidedWithWhy() async throws {
        try await givenProject()
        given(selectiveTestingService).listTests(
            fullHandle: .value("acme/app"),
            serverURL: .value(serverURL),
            testRunId: .value("run-1"),
            decision: .value(nil),
            reason: .value(nil),
            search: .value(nil),
            page: .value(1),
            pageSize: .value(20)
        ).willReturn(try decode(
            """
            {"tests":[
              {"test_case_id":"tc-1","module_name":"M","suite_name":"S","name":"test_a()",
               "decision":"selected","reason":"impacted","matched_path":"A.swift","shard_index":0,
               "estimated_duration":300,"outcome":"success","test_case_run_id":"tcr-1"},
              {"test_case_id":"tc-2","module_name":"M","suite_name":"S","name":"test_b()",
               "decision":"skipped","reason":"unaffected","matched_path":null,"shard_index":null,
               "estimated_duration":0,"outcome":null,"test_case_run_id":null}],
             "pagination_metadata":\(Self.pagination)}
            """
        ))
        let subject = TestSelectiveTestingListCommandService(
            selectiveTestingService: selectiveTestingService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )

        try await subject.run(
            project: nil, testRunId: "run-1", path: nil, decision: nil, reason: nil, search: nil,
            page: nil, pageSize: nil, json: false
        )

        #expect(ui().contains("M/S/test_a()"))
        #expect(ui().contains("impacted"))
        #expect(ui().contains("A.swift"))
        #expect(ui().contains("success"))
        #expect(ui().contains("M/S/test_b()"))
        #expect(ui().contains("unaffected"))
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func listsTheChangedFilesAndSaysWhyThereAreNone() async throws {
        try await givenProject()
        given(selectiveTestingService).listChangedFiles(
            fullHandle: .any,
            serverURL: .any,
            testRunId: .value("run-1"),
            search: .any,
            page: .any,
            pageSize: .any
        ).willReturn(try decode(
            """
            {"changed_files":[],
             "pagination_metadata":{"current_page":1,"has_next_page":false,"has_previous_page":false,"page_size":20,
                                    "total_count":0,"total_pages":0}}
            """
        ))
        let subject = TestSelectiveTestingFilesCommandService(
            selectiveTestingService: selectiveTestingService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )

        try await subject.run(project: nil, testRunId: "run-1", path: nil, search: nil, page: nil, pageSize: nil, json: false)

        #expect(ui().contains("No changed files found for test run run-1"))
    }

    @Test(.withMockedEnvironment())
    func failsWithoutAProject() async throws {
        try await givenProject(fullHandle: nil)
        let subject = TestSelectiveTestingListCommandService(
            selectiveTestingService: selectiveTestingService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )

        await #expect(throws: TestSelectiveTestingCommandServiceError.missingFullHandle) {
            try await subject.run(
                project: nil, testRunId: "run-1", path: nil, decision: nil, reason: nil, search: nil,
                page: nil, pageSize: nil, json: false
            )
        }
    }
}
