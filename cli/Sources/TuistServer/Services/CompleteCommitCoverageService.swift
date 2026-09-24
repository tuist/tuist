import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

/// A commit's coverage as the server reports it once its pipeline signalled completion.
public struct CommitCoverage: Equatable, Sendable {
    public let gitCommitSHA: String
    public let coverage: Double
    public let coveredLines: Int
    public let executableLines: Int
    public let schemes: [String]
    public let partialSchemes: [String]
    public let complete: Bool

    public init(
        gitCommitSHA: String,
        coverage: Double,
        coveredLines: Int,
        executableLines: Int,
        schemes: [String],
        partialSchemes: [String],
        complete: Bool
    ) {
        self.gitCommitSHA = gitCommitSHA
        self.coverage = coverage
        self.coveredLines = coveredLines
        self.executableLines = executableLines
        self.schemes = schemes
        self.partialSchemes = partialSchemes
        self.complete = complete
    }
}

enum CompleteCommitCoverageServiceError: LocalizedError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The coverage completion request failed with an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message):
            return message
        }
    }
}

@Mockable
public protocol CompleteCommitCoverageServicing {
    func completeCommitCoverage(fullHandle: String, serverURL: URL, gitCommitSHA: String) async throws -> CommitCoverage
}

/// Tells the server that a commit's coverage pipeline finished: every run that gathers coverage
/// has reported, so the commit's coverage is complete and the pull request's gates can be judged.
public struct CompleteCommitCoverageService: CompleteCommitCoverageServicing {
    private let fullHandleService: FullHandleServicing

    public init(fullHandleService: FullHandleServicing = FullHandleService()) {
        self.fullHandleService = fullHandleService
    }

    public func completeCommitCoverage(fullHandle: String, serverURL: URL, gitCommitSHA: String) async throws -> CommitCoverage {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let response = try await client.completeCommitCoverage(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    git_commit_sha: gitCommitSHA
                )
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(commit):
                return CommitCoverage(
                    gitCommitSHA: commit.git_commit_sha,
                    coverage: commit.coverage,
                    coveredLines: commit.covered_lines,
                    executableLines: commit.executable_lines,
                    schemes: commit.schemes,
                    partialSchemes: commit.partial_schemes,
                    complete: commit.complete
                )
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error): throw CompleteCommitCoverageServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error): throw CompleteCommitCoverageServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error): throw CompleteCommitCoverageServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CompleteCommitCoverageServiceError.unknownError(statusCode)
        }
    }
}
