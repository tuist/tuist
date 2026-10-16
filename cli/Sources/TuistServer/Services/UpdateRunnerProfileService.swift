import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

public typealias RunnerProfileUpdateResult = Operations.updateRunnerProfile.Output.Ok.Body.jsonPayload

@Mockable
public protocol UpdateRunnerProfileServicing {
    /// Sets whether jobs on each repository's default branch save the profile's cache volumes and replaces the
    /// additional branches that save them.
    func updateCacheWriterPolicy(
        accountHandle: String,
        serverURL: URL,
        profileName: String,
        defaultBranch: Bool,
        branches: [String]
    ) async throws -> RunnerProfileUpdateResult
}

enum UpdateRunnerProfileServiceError: LocalizedError, Equatable {
    case badRequest(String)
    case forbidden(String)
    case notFound(String)
    case unprocessableContent(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .badRequest(message), let .forbidden(message), let .notFound(message), let .unprocessableContent(message):
            return message
        case let .unknownError(statusCode):
            return "We could not update the runner profile due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public struct UpdateRunnerProfileService: UpdateRunnerProfileServicing {
    public init() {}

    public func updateCacheWriterPolicy(
        accountHandle: String,
        serverURL: URL,
        profileName: String,
        defaultBranch: Bool,
        branches: [String]
    ) async throws -> RunnerProfileUpdateResult {
        let client = Client.authenticated(serverURL: serverURL)
        let response = try await client.updateRunnerProfile(
            .init(
                path: .init(account_handle: accountHandle, profile_name: profileName),
                body: .json(.init(cache_writer_branches: branches, cache_writer_default_branch: defaultBranch))
            )
        )
        switch response {
        case let .ok(value): return try value.body.json
        case let .badRequest(value): throw UpdateRunnerProfileServiceError.badRequest(try value.body.json.message)
        case let .forbidden(value): throw UpdateRunnerProfileServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw UpdateRunnerProfileServiceError.notFound(try value.body.json.message)
        case let .unprocessableContent(value):
            throw UpdateRunnerProfileServiceError.unprocessableContent(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw UpdateRunnerProfileServiceError.unknownError(statusCode)
        }
    }
}
