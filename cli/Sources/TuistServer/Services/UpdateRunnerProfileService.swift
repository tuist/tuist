import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

public typealias RunnerProfileUpdateResult = Operations.updateRunnerProfile.Output.Ok.Body.jsonPayload

@Mockable
public protocol UpdateRunnerProfileServicing {
    /// Replaces the branches whose jobs save the profile's cache volumes. `nil` follows each repository's default
    /// branch.
    func updateCacheWriterBranches(
        accountHandle: String,
        serverURL: URL,
        profileName: String,
        branches: [String]?
    ) async throws -> RunnerProfileUpdateResult
}

enum UpdateRunnerProfileServiceError: LocalizedError, Equatable {
    case forbidden(String)
    case notFound(String)
    case unprocessableContent(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .forbidden(message), let .notFound(message), let .unprocessableContent(message):
            return message
        case let .unknownError(statusCode):
            return "We could not update the runner profile due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public struct UpdateRunnerProfileService: UpdateRunnerProfileServicing {
    public init() {}

    public func updateCacheWriterBranches(
        accountHandle: String,
        serverURL: URL,
        profileName: String,
        branches: [String]?
    ) async throws -> RunnerProfileUpdateResult {
        let client = Client.authenticated(serverURL: serverURL)
        let body: Operations.updateRunnerProfile.Input.Body.jsonPayload = if let branches {
            .init(cache_writer_branches: branches)
        } else {
            .init(follow_default_branch: true)
        }
        let response = try await client.updateRunnerProfile(
            .init(path: .init(account_handle: accountHandle, profile_name: profileName), body: .json(body))
        )
        switch response {
        case let .ok(value): return try value.body.json
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
