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

struct BuildRunsCommandServiceTests {
    private let cargoBuildsService = MockCargoBuildsServicing()
    private let mixBuildsService = MockMixBuildsServicing()
    private let onceRunsService = MockOnceRunsServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let serverURL = URL(string: "https://tuist.example.com")!

    private static let pagination = #"{"current_page":1,"has_next_page":false,"has_previous_page":false,"page_size":10,"total_count":1,"total_pages":1}"#
    private static let actor = #"{"name":"marek","source":"verified","verified_account_handle":"marek","claimed_actor_id":"","submission_auth":"token"}"#

    private func givenProject(fullHandle: String? = "acme/app") async throws {
        let config = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(config)
        given(serverEnvironmentService).url(configServerURL: .any).willReturn(serverURL)
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    private func cargoBuild(_ extra: String = "") -> String {
        """
        {"id":"0190a5c4-0000-7000-8000-000000000001","actor":\(Self.actor),"command":"build","rust_version":"1.84.0",
         "status":"success","duration_ms":1500,"is_ci":true,"git_branch":"main","git_commit_sha":"abc123","git_ref":null,
         "ci_provider":null,"ci_run_id":null,"ci_project_handle":null,"ci_host":null,
         "started_at":"2026-10-19T10:00:00Z","inserted_at":"2026-10-19T10:00:02Z"\(extra)}
        """
    }

    @Test(.withMockedEnvironment())
    func requiresAFullHandle() async throws {
        try await givenProject(fullHandle: nil)
        let subject = BuildCargoListCommandService(
            cargoBuildsService: cargoBuildsService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )

        await #expect(throws: BuildRunsContextError.missingFullHandle) {
            try await subject.run(
                fullHandle: nil, path: nil, gitBranch: nil, status: nil, command: nil, page: nil, pageSize: nil, json: false
            )
        }
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func listsCargoBuildsWithTheirFilters() async throws {
        try await givenProject()
        given(cargoBuildsService).listCargoBuilds(
            fullHandle: .value("acme/app"),
            serverURL: .value(serverURL),
            gitBranch: .value("main"),
            status: .value("success"),
            command: .value("build"),
            page: .value(1),
            pageSize: .value(10)
        ).willReturn(try decode(#"{"builds":[\#(cargoBuild())],"pagination_metadata":\#(Self.pagination)}"#))
        let subject = BuildCargoListCommandService(
            cargoBuildsService: cargoBuildsService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )

        try await subject.run(
            fullHandle: nil, path: nil, gitBranch: "main", status: "success", command: "build", page: nil, pageSize: nil,
            json: true
        )

        #expect(ui().contains("0190a5c4-0000-7000-8000-000000000001"))
        #expect(ui().contains("1.84.0"))
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func showsACargoBuildWithItsCache() async throws {
        try await givenProject()
        let cache = #","cache":{"hits":3,"misses":1,"task_misses":1,"hit_rate":75.0,"downloaded_bytes":2048,"uploaded_bytes":0,"background_upload_failures":0,"divergences":0,"estimated_compiler_duration_avoided_ns":0,"materialization_duration_ns":0,"prefetch_duration_ns":0,"prefetched_actions":0,"remote_action_lookup_duration_ns":0,"remote_blob_transfer_duration_ns":0,"remote_failures":0,"unconsulted":0,"upload_drain_duration_ns":0,"verifications":0}"#
        given(cargoBuildsService).getCargoBuild(
            fullHandle: .value("acme/app"),
            serverURL: .value(serverURL),
            buildId: .value("build-1")
        )
        .willReturn(try decode(cargoBuild(cache)))
        let subject = BuildCargoShowCommandService(
            cargoBuildsService: cargoBuildsService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )

        try await subject.run(fullHandle: nil, buildId: "build-1", path: nil, json: false)

        #expect(ui().contains("Rust Version: 1.84.0"))
        #expect(ui().contains("Hit Rate: 75.0%"))
        #expect(ui().contains("Ran By: marek"))
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func explainsAMissingCargoCache() async throws {
        try await givenProject()
        given(cargoBuildsService).getCargoBuild(fullHandle: .any, serverURL: .any, buildId: .any)
            .willReturn(try decode(cargoBuild(#","cache":null"#)))
        let subject = BuildCargoShowCommandService(
            cargoBuildsService: cargoBuildsService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )

        try await subject.run(fullHandle: nil, buildId: "build-1", path: nil, json: false)

        #expect(ui().contains("The build reported no cache measurements."))
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func reportsAnEmptyMixBuildList() async throws {
        try await givenProject()
        given(mixBuildsService).listMixBuilds(
            fullHandle: .any, serverURL: .any, gitBranch: .any, status: .any, mixEnv: .value("test"), page: .any, pageSize: .any
        ).willReturn(try decode(
            #"{"builds":[],"pagination_metadata":{"current_page":1,"has_next_page":false,"has_previous_page":false,"page_size":10,"total_count":0,"total_pages":0}}"#
        ))
        let subject = BuildMixListCommandService(
            mixBuildsService: mixBuildsService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )

        try await subject.run(
            fullHandle: nil, path: nil, gitBranch: nil, status: nil, mixEnv: "test", page: nil, pageSize: nil, json: false
        )

        #expect(ui().contains("No Mix builds found for project acme/app."))
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func showsAOnceTestRunWithItsTotals() async throws {
        try await givenProject()
        given(onceRunsService).getOnceRun(fullHandle: .value("acme/app"), serverURL: .value(serverURL), runId: .value("run-1"))
            .willReturn(try decode(
                """
                {"run_id":"run-1","kind":"test","command":"once test","status":"failure","duration_ms":2500,"is_ci":false,
                 "git_rev":"abc123","git_branch":"main","host_class":"macos-arm64","started_at":"2026-10-19T10:00:00Z",
                 "finished_at":"2026-10-19T10:00:03Z","once_version":"0.9.0","git_dirty":true,"exit_status":1,
                 "cancellation_reason":null,"actions":{"total":4,"cached":3,"executed":1,"failed":1},
                 "cache":{"hits":3,"misses":1,"total_lookups":4,"hit_rate":75.0,"content_download_bytes":2048,
                          "content_upload_bytes":512,"content_saved_bytes":4096},
                 "tests":{"test_cases":10,"passed":9,"failed":1,"skipped":0,"test_suites":2}}
                """
            ))
        let subject = BuildOnceShowCommandService(
            onceRunsService: onceRunsService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )

        try await subject.run(fullHandle: nil, runId: "run-1", path: nil, json: false)

        #expect(ui().contains("Git Revision: abc123 (dirty)"))
        #expect(ui().contains("Hits: 3 of 4 lookups"))
        #expect(ui().contains("Passed: 9"))
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func listsOnceRunsOfOneKind() async throws {
        try await givenProject()
        given(onceRunsService).listOnceRuns(
            fullHandle: .any, serverURL: .any, kind: .value("build"), status: .any, gitBranch: .any, page: .value(1),
            pageSize: .value(10)
        ).willReturn(try decode(
            """
            {"runs":[{"run_id":"run-2","kind":"build","command":"once build","status":"success","duration_ms":800,
                      "is_ci":true,"git_rev":"def456","git_branch":"main","host_class":null,
                      "started_at":"2026-10-19T09:00:00Z","finished_at":"2026-10-19T09:00:01Z",
                      "cache":{"hit_rate":50.0,"download_bytes":0,"upload_bytes":0}}],
             "pagination_metadata":\(Self.pagination)}
            """
        ))
        let subject = BuildOnceListCommandService(
            onceRunsService: onceRunsService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )

        try await subject.run(
            fullHandle: nil, path: nil, kind: "build", status: nil, gitBranch: nil, page: nil, pageSize: nil, json: true
        )

        #expect(ui().contains("run-2"))
        #expect(ui().contains("once build"))
    }
}
