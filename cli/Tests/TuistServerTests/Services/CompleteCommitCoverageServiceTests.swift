import Foundation
import OpenAPIRuntime
import Testing

@testable import TuistServer

struct CompleteCommitCoverageServiceTests {
    private typealias Output = Operations.completeCommitCoverage.Output

    @Test func returnsTheCommitsCoverageOnceComplete() throws {
        let response = Output.ok(.init(body: .json(.init(
            complete: true,
            completeness: "complete",
            coverage: 82.5,
            covered_lines: 165,
            executable_lines: 200,
            git_commit_sha: "abcdef1234567",
            measured_files_count: 12,
            partial: true,
            partial_schemes: ["Core"],
            schemes: ["App", "Core"],
            targets: [],
            test_run_ids: ["run-1"],
            unmeasured_files_count: 0
        ))))

        #expect(try CompleteCommitCoverageService.completion(from: response) == .complete(CommitCoverage(
            gitCommitSHA: "abcdef1234567",
            coverage: 82.5,
            coveredLines: 165,
            executableLines: 200,
            schemes: ["App", "Core"],
            partialSchemes: ["Core"],
            complete: true
        )))
    }

    @Test func takesTheReportedFigureWhenSkippedTestsWereCarried() throws {
        let response = Output.ok(.init(body: .json(.init(
            complete: true,
            completeness: "complete",
            coverage: 31.9,
            covered_lines: 45914,
            executable_lines: 143_800,
            git_commit_sha: "abcdef1234567",
            measured_files_count: 12,
            partial: true,
            partial_schemes: ["App"],
            reported: .init(
                carried_from: ["0123456789abc"],
                carried_tests_count: 1771,
                coverage: 43.5,
                covered_lines: 64055,
                executable_lines: 147_122,
                gap_files_count: 0,
                kind: .reported,
                skipped_tests_count: 1771
            ),
            schemes: ["App"],
            targets: [],
            test_run_ids: ["run-1"],
            unmeasured_files_count: 0
        ))))

        #expect(try CompleteCommitCoverageService.completion(from: response) == .complete(CommitCoverage(
            gitCommitSHA: "abcdef1234567",
            coverage: 43.5,
            coveredLines: 64055,
            executableLines: 147_122,
            schemes: ["App"],
            partialSchemes: ["App"],
            complete: true
        )))
    }

    @Test func marksAPartialReportedFigureIncomplete() throws {
        let response = Output.ok(.init(body: .json(.init(
            complete: true,
            completeness: "complete",
            coverage: 31.9,
            covered_lines: 45914,
            executable_lines: 143_800,
            git_commit_sha: "abcdef1234567",
            measured_files_count: 12,
            partial: true,
            partial_schemes: ["App"],
            reported: .init(
                carried_from: [],
                carried_tests_count: 1700,
                coverage: 42.0,
                covered_lines: 61800,
                executable_lines: 147_122,
                gap_files_count: 0,
                kind: .partial,
                skipped_tests_count: 1771
            ),
            schemes: ["App"],
            targets: [],
            test_run_ids: ["run-1"],
            unmeasured_files_count: 0
        ))))

        guard case let .complete(coverage) = try CompleteCommitCoverageService.completion(from: response) else {
            Issue.record("Expected a complete coverage")
            return
        }
        #expect(coverage.coverage == 42.0)
        #expect(coverage.incomplete)
    }

    @Test func isPendingWhenTheServerKeptTheSignal() throws {
        let response = Output.accepted(.init(body: .json(.init(message: "No run has reported coverage yet."))))

        #expect(try CompleteCommitCoverageService.completion(from: response) == .pending)
    }

    @Test func carriesTheServersMessageOnAClientError() {
        #expect(throws: CompleteCommitCoverageServiceError.notFound("Project not found")) {
            try CompleteCommitCoverageService.completion(
                from: .notFound(.init(body: .json(.init(message: "Project not found"))))
            )
        }
        #expect(throws: CompleteCommitCoverageServiceError.forbidden("Not allowed")) {
            try CompleteCommitCoverageService.completion(
                from: .forbidden(.init(body: .json(.init(message: "Not allowed"))))
            )
        }
        #expect(throws: CompleteCommitCoverageServiceError.unauthorized("Sign in")) {
            try CompleteCommitCoverageService.completion(
                from: .unauthorized(.init(body: .json(.init(message: "Sign in"))))
            )
        }
    }

    @Test func reportsAnUndocumentedStatus() {
        #expect(throws: CompleteCommitCoverageServiceError.unknownError(500)) {
            try CompleteCommitCoverageService.completion(from: .undocumented(statusCode: 500, .init()))
        }
    }
}
