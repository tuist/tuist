import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

/// A test run a CI pipeline is about to make: the id it will be created with, and the scheme it was
/// asked to test.
public struct ExpectedCoverageRun: Equatable, Sendable {
    public let id: String
    public let scheme: String

    public init(id: String, scheme: String) {
        self.id = id
        self.scheme = scheme
    }
}

enum ExpectCommitCoverageRunsServiceError: Equatable, LocalizedError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "Registering the coverage runs failed with an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message):
            return message
        }
    }
}

@Mockable
public protocol ExpectCommitCoverageRunsServicing {
    func expectCommitCoverageRuns(
        fullHandle: String,
        serverURL: URL,
        gitCommitSHA: String,
        runs: [ExpectedCoverageRun]
    ) async throws
}

/// Registers the runs a commit's coverage pipeline started, before they build: a run whose report
/// never reaches the server leaves its scheme missing from the commit's coverage, which is then
/// incomplete rather than complete with what the other schemes measured.
public struct ExpectCommitCoverageRunsService: ExpectCommitCoverageRunsServicing {
    private let fullHandleService: FullHandleServicing

    public init(fullHandleService: FullHandleServicing = FullHandleService()) {
        self.fullHandleService = fullHandleService
    }

    public func expectCommitCoverageRuns(
        fullHandle: String,
        serverURL: URL,
        gitCommitSHA: String,
        runs: [ExpectedCoverageRun]
    ) async throws {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let response = try await client.expectCommitCoverageRuns(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    git_commit_sha: gitCommitSHA
                ),
                body: .json(.init(runs: runs.map { .init(id: $0.id, scheme: $0.scheme) }))
            )
        )
        try Self.validate(response)
    }

    static func validate(_ response: Operations.expectCommitCoverageRuns.Output) throws {
        switch response {
        case .noContent:
            return
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error): throw ExpectCommitCoverageRunsServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error): throw ExpectCommitCoverageRunsServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error): throw ExpectCommitCoverageRunsServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ExpectCommitCoverageRunsServiceError.unknownError(statusCode)
        }
    }
}
