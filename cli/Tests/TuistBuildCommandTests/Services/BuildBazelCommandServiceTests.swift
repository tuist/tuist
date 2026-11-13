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

struct BuildBazelCommandServiceTests {
    private let bazelInvocationsService = MockBazelInvocationsServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let serverURL = URL(string: "https://tuist.example.com")!

    private func givenProject() async throws {
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(Tuist.test(fullHandle: "acme/app"))
        given(serverEnvironmentService).url(configServerURL: .any).willReturn(serverURL)
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    private static func pagination(page: Int, totalPages: Int) -> String {
        """
        {"current_page":\(page),"has_next_page":\(page < totalPages),"has_previous_page":\(page > 1),"page_size":100,\
        "total_count":null,"total_pages":\(totalPages)}
        """
    }

    private static func invocation(status: String = "failure", criticalPath: String = "null") -> String {
        """
        {"invocation_id":"inv-1","command":"build","target_patterns":["//app/...","//lib:core"],"git_branch":"main",
         "git_commit_sha":"abc123","is_ci":true,"custom_metadata":{"tags":[],"values":{}},"bazel_version":"8.1.0",
         "cache_endpoint":"","status":"\(status)","exit_code":1,"started_at":"2026-11-01T10:00:00Z",
         "finished_at":"2026-11-01T10:01:00Z","duration_ms":60000,
         "build_metrics":{"cpu_time_ms":1000,"actions_created":12,"actions_executed":7,"targets_configured":3,"packages_loaded":2},
         "build_timeline":null,"critical_path":\(criticalPath),
         "cache":{"hits":3,"misses":1,"download_bytes":2048,"upload_bytes":0,"hit_rate":75.0}}
        """
    }

    private static func log(_ sequenceNumber: Int, _ message: String) -> String {
        """
        {"id":"0190a5c4-0000-7000-8000-00000000000\(sequenceNumber)","invocation_id":"inv-1",
         "sequence_number":\(sequenceNumber),"stream":"stderr","message":"\(message)","observed_at":"2026-11-01T10:00:00Z"}
        """
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func listsBazelInvocationsWithTheirFilters() async throws {
        try await givenProject()
        given(bazelInvocationsService).listBazelInvocations(
            fullHandle: .value("acme/app"),
            serverURL: .value(serverURL),
            gitBranch: .value("main"),
            status: .value("failure"),
            page: .value(2),
            pageSize: .value(5)
        ).willReturn(try decode(
            #"{"invocations":[\#(Self.invocation())],"pagination_metadata":\#(Self.pagination(page: 2, totalPages: 2))}"#
        ))
        let subject = BuildBazelListCommandService(
            bazelInvocationsService: bazelInvocationsService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )

        try await subject.run(
            fullHandle: nil, path: nil, gitBranch: "main", status: "failure", page: 2, pageSize: 5, json: true
        )

        #expect(ui().contains("inv-1"))
        #expect(ui().contains("8.1.0"))
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func showsAFailedInvocationWithItsCriticalPathAndNextSteps() async throws {
        try await givenProject()
        let criticalPath = #"{"duration_ms":4500,"actions":[{"description":"Compiling lib/core.swift","duration_ms":4000}]}"#
        given(bazelInvocationsService).getBazelInvocation(
            fullHandle: .value("acme/app"),
            serverURL: .value(serverURL),
            invocationId: .value("inv-1")
        ).willReturn(try decode(Self.invocation(criticalPath: criticalPath)))
        let subject = BuildBazelShowCommandService(
            bazelInvocationsService: bazelInvocationsService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )

        try await subject.run(fullHandle: nil, invocationId: "inv-1", path: nil, json: false)

        #expect(ui().contains("Status: failure (exit code 1)"))
        #expect(ui().contains("Targets: //app/... //lib:core"))
        #expect(ui().contains("Hit Rate: 75.0%"))
        #expect(ui().contains("Actions Executed: 7"))
        #expect(ui().contains("Compiling lib/core.swift"))
        #expect(ui().contains("tuist build bazel step list inv-1 --status failure"))
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func printsTheLogsOfEveryPageInOrder() async throws {
        try await givenProject()
        given(bazelInvocationsService).listBazelInvocationLogs(
            fullHandle: .value("acme/app"), serverURL: .value(serverURL), invocationId: .value("inv-1"), page: .value(1),
            pageSize: .any
        ).willReturn(try decode(
            #"{"logs":[\#(Self.log(1, "Analyzing 2 targets\\n")),\#(Self.log(2, "ERROR: lib/BUILD:3:1: "))],"pagination_metadata":\#(Self.pagination(page: 1, totalPages: 2))}"#
        ))
        given(bazelInvocationsService).listBazelInvocationLogs(
            fullHandle: .value("acme/app"), serverURL: .value(serverURL), invocationId: .value("inv-1"), page: .value(2),
            pageSize: .any
        ).willReturn(try decode(
            #"{"logs":[\#(Self.log(3, "Compiling failed\\n"))],"pagination_metadata":\#(Self.pagination(page: 2, totalPages: 2))}"#
        ))
        let subject = BuildBazelLogsCommandService(
            bazelInvocationsService: bazelInvocationsService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )

        try await subject.run(fullHandle: nil, invocationId: "inv-1", path: nil, json: false)

        #expect(ui().contains("Analyzing 2 targets\nERROR: lib/BUILD:3:1: Compiling failed"))
        verify(bazelInvocationsService).listBazelInvocationLogs(
            fullHandle: .any, serverURL: .any, invocationId: .any, page: .any, pageSize: .any
        ).called(2)
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func listsFailedStepsAndExplainsProcessingSteps() async throws {
        try await givenProject()
        given(bazelInvocationsService).listBazelBuildSteps(
            fullHandle: .value("acme/app"), serverURL: .value(serverURL), invocationId: .value("inv-1"),
            status: .value("failure"), target: .value("//lib:core"), search: .value(nil), sortBy: .value("start_ms"),
            page: .value(1), pageSize: .value(10)
        ).willReturn(try decode(
            """
            {"availability":"available","coverage":"trace_profile","time_origin":"profile_start",
             "pagination_metadata":\(Self.pagination(page: 1, totalPages: 1)),
             "steps":[{"id":"step-1","title":"Compiling lib/core.swift","project":"lib","target":"//lib:core",
                       "category":"SwiftCompile","status":"failure","start_ms":10,"duration_ms":4000.6}]}
            """
        ))
        given(bazelInvocationsService).listBazelBuildSteps(
            fullHandle: .any, serverURL: .any, invocationId: .value("inv-2"), status: .any, target: .any, search: .any,
            sortBy: .any, page: .any, pageSize: .any
        ).willReturn(try decode(
            """
            {"availability":"processing","coverage":"retained_action_spans","time_origin":"build_start",
             "pagination_metadata":\(Self.pagination(page: 1, totalPages: 0)),"steps":[]}
            """
        ))
        let subject = BuildBazelStepListCommandService(
            bazelInvocationsService: bazelInvocationsService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )

        try await subject.run(
            fullHandle: nil, invocationId: "inv-1", path: nil, status: "failure", target: "//lib:core", search: nil,
            sortBy: "start_ms", page: nil, pageSize: nil, json: true
        )
        try await subject.run(
            fullHandle: nil, invocationId: "inv-2", path: nil, status: nil, target: nil, search: nil, sortBy: nil,
            page: nil, pageSize: nil, json: false
        )

        #expect(ui().contains("step-1"))
        #expect(ui().contains("The steps of Bazel invocation inv-2 are still being processed."))
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func showsAStepWithItsTruncatedLog() async throws {
        try await givenProject()
        given(bazelInvocationsService).getBazelBuildStep(
            fullHandle: .value("acme/app"), serverURL: .value(serverURL), invocationId: .value("inv-1"),
            stepId: .value("step-1")
        ).willReturn(try decode(
            #"""
            {"id":"step-1","title":"Compiling lib/core.swift","project":"lib","target":"//lib:core","category":"SwiftCompile",
             "status":"failure","start_ms":10,"duration_ms":4000,"log":"core.swift:3: error: cannot find 'x'\n",
             "log_truncated":true}
            """#
        ))
        let subject = BuildBazelStepShowCommandService(
            bazelInvocationsService: bazelInvocationsService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )

        try await subject.run(fullHandle: nil, invocationId: "inv-1", stepId: "step-1", path: nil, json: false)

        #expect(ui().contains("Target: //lib:core"))
        #expect(ui().contains("core.swift:3: error: cannot find 'x'\nThe log was truncated."))
    }
}
