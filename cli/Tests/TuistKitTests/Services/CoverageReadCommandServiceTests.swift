import Foundation
import Mockable
import Testing
import TuistConfig
import TuistConfigLoader
import TuistEnvironment
import TuistEnvironmentTesting
import TuistNooraTesting
import TuistServer
import TuistTesting

@testable import TuistKit

struct CoverageReadCommandServiceTests {
    private let coverageService = MockCoverageServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let serverURL = URL(string: "https://tuist.example.com")!

    private func givenProject(fullHandle: String? = "acme/app") async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
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

    private static func commit(sha: String, branch: String? = nil) -> String {
        let branchField = branch.map { #""branch":"\#($0)","# } ?? ""
        return """
        {\(branchField)"git_commit_sha":"\(sha)","coverage":82.5,"covered_lines":165,"executable_lines":200,
         "measured_files_count":12,"unmeasured_files_count":0,"complete":true,"completeness":"complete","partial":false,
         "partial_schemes":[],"schemes":["App"],"test_run_ids":[],"measured_at":"2026-10-19T10:00:00Z","reported":null,
         "targets":[{"name":"App","files_count":12,"covered_lines":165,"executable_lines":200,"coverage":82.5}]}
        """
    }

    @Test(.withMockedEnvironment())
    func refusesWithoutTheCoverageFlag() async throws {
        let subject = CoverageShowCommandService(
            coverageService: coverageService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )

        await #expect(throws: CoverageReadCommandServiceError.earlyAccess) {
            try await subject.run(path: nil, fullHandle: "acme/app", branch: nil, commit: nil, json: false)
        }
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func showsTheBranchsLatestCompleteCommit() async throws {
        try await givenProject()
        given(coverageService).getBranchCoverage(
            fullHandle: .value("acme/app"),
            serverURL: .value(serverURL),
            branch: .value(nil)
        )
        .willReturn(try decode(Self.commit(sha: "abc123", branch: "main")))
        let subject = CoverageShowCommandService(
            coverageService: coverageService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )

        try await subject.run(path: nil, fullHandle: nil, branch: nil, commit: nil, json: false)

        #expect(ui().contains("Branch: main"))
        #expect(ui().contains("Coverage: 82.5% (165 of 200 lines)"))
        #expect(ui().contains("App: 82.5% (165 of 200 lines)"))
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func listsTheFilesOfTheBranchsLatestCompleteCommit() async throws {
        try await givenProject()
        given(coverageService).getBranchCoverage(fullHandle: .any, serverURL: .any, branch: .value("release"))
            .willReturn(try decode(Self.commit(sha: "def456", branch: "release")))
        given(coverageService).listCoverageFiles(
            fullHandle: .value("acme/app"),
            serverURL: .value(serverURL),
            commitSHA: .value("def456"),
            search: .value("Sources"),
            sortBy: .value("path"),
            sortOrder: .value(nil),
            page: .value(1),
            pageSize: .value(20)
        ).willReturn(try decode(
            """
            {"git_commit_sha":"def456",
             "files":[{"path":"Sources/App.swift","coverage":50.0,"covered_lines":5,"executable_lines":10}],
             "pagination_metadata":{"current_page":1,"has_next_page":false,"has_previous_page":false,"page_size":20,
                                    "total_count":1,"total_pages":1}}
            """
        ))
        let subject = CoverageFilesCommandService(
            coverageService: coverageService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )

        try await subject.run(
            path: nil, fullHandle: nil, branch: "release", commit: nil, search: "Sources", sortBy: "path",
            sortOrder: nil, page: nil, pageSize: nil, json: true
        )

        #expect(ui().contains("App.swift"))
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func showsAFileWithItsUncoveredLines() async throws {
        try await givenProject()
        given(coverageService).getCoverageFile(
            fullHandle: .any,
            serverURL: .any,
            commitSHA: .value("abc123"),
            path: .value("Sources/App.swift"),
            includeLines: .value(true)
        ).willReturn(try decode(
            """
            {"git_commit_sha":"abc123","path":"Sources/App.swift","git_blob_id":null,"targets":["App"],
             "covered_lines":3,"executable_lines":7,"coverage":42.9,"carried_lines":[],
             "functions":[{"name":"run()","line_number":3,"execution_count":2,"covered_lines":3,"executable_lines":7}],
             "lines":[{"line":3,"count":2},{"line":4,"count":0},{"line":5,"count":0},{"line":6,"count":0},
                      {"line":8,"count":1},{"line":9,"count":0},{"line":10,"count":4}]}
            """
        ))
        let subject = CoverageFileCommandService(
            coverageService: coverageService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )

        try await subject.run(
            path: nil, fullHandle: nil, branch: nil, commit: "abc123", filePath: "Sources/App.swift",
            includeLines: true, json: false
        )

        #expect(ui().contains("Uncovered Lines: 4-6, 9"))
        #expect(ui().contains("run() (line 3): called 2 times"))
    }
}
