import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

public typealias RunnerProfileListResult = Operations.listRunnerProfiles.Output.Ok.Body.jsonPayload

@Mockable
public protocol ListRunnerProfilesServicing {
    func listRunnerProfiles(accountHandle: String, serverURL: URL) async throws -> RunnerProfileListResult
}

enum ListRunnerProfilesServiceError: LocalizedError, Equatable {
    case forbidden(String)
    case notFound(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .forbidden(message), let .notFound(message):
            return message
        case let .unknownError(statusCode):
            return "We could not list the runner profiles due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public struct ListRunnerProfilesService: ListRunnerProfilesServicing {
    public init() {}

    public func listRunnerProfiles(accountHandle: String, serverURL: URL) async throws -> RunnerProfileListResult {
        let client = Client.authenticated(serverURL: serverURL)
        let response = try await client.listRunnerProfiles(.init(path: .init(account_handle: accountHandle)))
        switch response {
        case let .ok(value): return try value.body.json
        case let .forbidden(value): throw ListRunnerProfilesServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw ListRunnerProfilesServiceError.notFound(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw ListRunnerProfilesServiceError.unknownError(statusCode)
        }
    }
}
