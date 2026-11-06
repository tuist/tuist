import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

public typealias RunnerCatalogResult = Operations.getRunnerCatalog.Output.Ok.Body.jsonPayload

@Mockable
public protocol GetRunnerCatalogServicing {
    /// Gets the machine shapes and Xcode versions runner profiles can use.
    func getRunnerCatalog(accountHandle: String, serverURL: URL) async throws -> RunnerCatalogResult
}

enum GetRunnerCatalogServiceError: LocalizedError, Equatable {
    case forbidden(String)
    case notFound(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .forbidden(message), let .notFound(message):
            return message
        case let .unknownError(statusCode):
            return "We could not get the runner catalog due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public struct GetRunnerCatalogService: GetRunnerCatalogServicing {
    public init() {}

    public func getRunnerCatalog(accountHandle: String, serverURL: URL) async throws -> RunnerCatalogResult {
        let client = Client.authenticated(serverURL: serverURL)
        let response = try await client.getRunnerCatalog(.init(path: .init(account_handle: accountHandle)))
        switch response {
        case let .ok(value): return try value.body.json
        case let .forbidden(value): throw GetRunnerCatalogServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw GetRunnerCatalogServiceError.notFound(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw GetRunnerCatalogServiceError.unknownError(statusCode)
        }
    }
}
