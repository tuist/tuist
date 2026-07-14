import Foundation
import Mockable
import OpenAPIRuntime

@Mockable
public protocol GetCacheEndpointsServicing: Sendable {
    func getCacheEndpoints(
        serverURL: URL,
        accountHandle: String?
    ) async throws -> [String]
}

enum GetCacheEndpointsServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "Failed to retrieve cache endpoints due to an unknown server response of \(statusCode)."
        case let .forbidden(message):
            return message
        }
    }
}

public struct GetCacheEndpointsService: GetCacheEndpointsServicing {
    public init() {}

    public func getCacheEndpoints(
        serverURL: URL,
        accountHandle: String?
    ) async throws -> [String] {
        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.getCacheEndpoints(
            .init(query: .init(account_handle: accountHandle))
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(endpoints):
                return endpoints.endpoints
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw GetCacheEndpointsServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetCacheEndpointsServiceError.unknownError(statusCode)
        }
    }
}
