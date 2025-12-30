import Foundation
import Mockable
import OpenAPIURLSession

@Mockable
public protocol GetCacheEndpointsServicing: Sendable {
    func getCacheEndpoints(
        serverURL: URL,
        accountHandle: String?
    ) async throws -> [String]
}

enum GetCacheEndpointsServiceError: LocalizedError {
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "Failed to retrieve cache endpoints due to an unknown server response of \(statusCode)."
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
        case let .undocumented(statusCode: statusCode, _):
            throw GetCacheEndpointsServiceError.unknownError(statusCode)
        }
    }
}
