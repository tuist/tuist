import Foundation
import Logging
import TuistLogging
import TuistServer

public protocol CacheURLStoring: Sendable {
    func getCacheURL(for serverURL: URL, accountHandle: String?) async throws -> URL
}

public struct CacheURLStore: CacheURLStoring {
    private let getCacheEndpointsService: GetCacheEndpointsServicing

    public init(
        getCacheEndpointsService: GetCacheEndpointsServicing = GetCacheEndpointsService()
    ) {
        self.getCacheEndpointsService = getCacheEndpointsService
    }

    public func getCacheURL(for serverURL: URL, accountHandle: String?) async throws -> URL {
        Logger.current.debug("Getting cache endpoint for \(serverURL.absoluteString)")

        let endpoints = try await getCacheEndpointsService.getCacheEndpoints(
            serverURL: serverURL,
            accountHandle: accountHandle
        )

        guard !endpoints.isEmpty else {
            throw CacheURLStoreError.noEndpointsAvailable
        }

        guard let endpoint = endpoints.first, let url = URL(string: endpoint) else {
            throw CacheURLStoreError.invalidURL(endpoints.first ?? "")
        }

        Logger.current.debug("Using cache endpoint: \(url.absoluteString)")
        return url
    }
}

enum CacheURLStoreError: LocalizedError, Equatable {
    case noEndpointsAvailable
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .noEndpointsAvailable:
            return "No cache endpoints are available."
        case let .invalidURL(url):
            return "Invalid cache endpoint URL: \(url)."
        }
    }
}
