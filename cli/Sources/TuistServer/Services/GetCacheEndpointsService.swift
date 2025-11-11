import Foundation
import Mockable
import OpenAPIURLSession

@Mockable
public protocol GetCacheEndpointsServicing {
    func getCacheEndpoints(
        serverURL: URL
    ) async throws -> [String]
}

enum GetCacheEndpointsServiceError: LocalizedError {
    case unknownError(Int)
    case noEndpointsAvailable

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "Failed to retrieve cache endpoints due to an unknown server response of \(statusCode)."
        case .noEndpointsAvailable:
            return "No cache endpoints are available."
        }
    }
}

public final class GetCacheEndpointsService: GetCacheEndpointsServicing {
    public init() {}

    public func getCacheEndpoints(
        serverURL: URL
    ) async throws -> [String] {
        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.getCacheEndpoints(.init())

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(endpoints):
                guard let endpointsList = endpoints.data?.endpoints, !endpointsList.isEmpty else {
                    throw GetCacheEndpointsServiceError.noEndpointsAvailable
                }
                return endpointsList
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetCacheEndpointsServiceError.unknownError(statusCode)
        }
    }
}
