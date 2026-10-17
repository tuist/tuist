import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

public typealias RunnerProfileOptionsResult = Operations.listRunnerProfileOptions.Output.Ok.Body.jsonPayload

@Mockable
public protocol ListRunnerProfileOptionsServicing {
    /// Lists the machine shapes and Xcode versions runner profiles can use.
    func listRunnerProfileOptions(accountHandle: String, serverURL: URL) async throws -> RunnerProfileOptionsResult
}

enum ListRunnerProfileOptionsServiceError: LocalizedError, Equatable {
    case forbidden(String)
    case notFound(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .forbidden(message), let .notFound(message):
            return message
        case let .unknownError(statusCode):
            return "We could not list the runner profile options due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public struct ListRunnerProfileOptionsService: ListRunnerProfileOptionsServicing {
    public init() {}

    public func listRunnerProfileOptions(accountHandle: String, serverURL: URL) async throws -> RunnerProfileOptionsResult {
        let client = Client.authenticated(serverURL: serverURL)
        let response = try await client.listRunnerProfileOptions(.init(path: .init(account_handle: accountHandle)))
        switch response {
        case let .ok(value): return try value.body.json
        case let .forbidden(value): throw ListRunnerProfileOptionsServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw ListRunnerProfileOptionsServiceError.notFound(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw ListRunnerProfileOptionsServiceError.unknownError(statusCode)
        }
    }
}
