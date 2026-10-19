import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol DeleteRunnerProfileServicing {
    func deleteRunnerProfile(accountHandle: String, serverURL: URL, profileName: String) async throws
}

enum DeleteRunnerProfileServiceError: LocalizedError, Equatable {
    case forbidden(String)
    case notFound(String)
    case unprocessableContent(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .forbidden(message), let .notFound(message), let .unprocessableContent(message):
            return message
        case let .unknownError(statusCode):
            return "We could not delete the runner profile due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public struct DeleteRunnerProfileService: DeleteRunnerProfileServicing {
    public init() {}

    public func deleteRunnerProfile(accountHandle: String, serverURL: URL, profileName: String) async throws {
        let client = Client.authenticated(serverURL: serverURL)
        let response = try await client.deleteRunnerProfile(
            .init(path: .init(account_handle: accountHandle, profile_name: profileName))
        )
        switch response {
        case .noContent: return
        case let .forbidden(value): throw DeleteRunnerProfileServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw DeleteRunnerProfileServiceError.notFound(try value.body.json.message)
        case let .unprocessableContent(value):
            throw DeleteRunnerProfileServiceError.unprocessableContent(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw DeleteRunnerProfileServiceError.unknownError(statusCode)
        }
    }
}
