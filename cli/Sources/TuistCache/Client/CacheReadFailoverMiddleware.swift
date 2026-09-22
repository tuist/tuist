import Foundation
import HTTPTypes
import OpenAPIRuntime
import TuistLogging
import TuistServer

/// Gives a failed read one attempt at another account endpoint after normal retries.
/// It sits outside authentication and body resumption: credentials are acquired for
/// the new attempt, and a partial response is never spliced across regional copies.
struct CacheReadFailoverMiddleware: ClientMiddleware {
    private static let sharedResolutions = CachedValueStore(backend: .inSystemProcess)

    let authenticationURL: URL
    let fullHandle: String?
    var endpointsService: GetCacheEndpointsServicing = GetCacheEndpointsService()
    var resolutions: CachedValueStoring = Self.sharedResolutions

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let handle = fullHandle?.split(separator: "/", omittingEmptySubsequences: false)
        guard request.method == .get, body == nil, request.headerFields[.range] == nil,
              let handle, handle.count == 2, !handle[0].isEmpty, !handle[1].isEmpty
        else { return try await next(request, body, baseURL) }

        let original: Result<(HTTPResponse, HTTPBody?), any Error>
        do {
            let response = try await next(request, nil, baseURL)
            guard [502, 503, 504].contains(response.0.status.code),
                  response.0.headerFields[HTTPField.Name("x-tuist-throttle-reason")!] != "authorization"
            else { return response }
            original = .success(response)
        } catch {
            guard let error = error as? URLError,
                  [.timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .networkConnectionLost]
                  .contains(error.code)
            else { throw error }
            original = .failure(error)
        }

        try Task.checkCancellation()
        guard let alternative = try await alternativeEndpoint(account: String(handle[0]), excluding: baseURL) else {
            return try original.get()
        }
        Logger.current.debug("Retrying the cache read through another account endpoint: \(alternative.host ?? "")")
        return try await next(request, nil, alternative)
    }

    private func alternativeEndpoint(account: String, excluding failed: URL) async throws -> URL? {
        do {
            // Share discovery across concurrent failed reads, but do not keep a
            // failure-time routing answer for the normal one-hour endpoint TTL.
            let endpoints: [String]? = try await resolutions.getValue(
                key: "cache_read_failover_\(authenticationURL.absoluteString)_\(account)"
            ) {
                let resolution = try await endpointsService.getCacheEndpoints(
                    serverURL: authenticationURL, accountHandle: account
                )
                let maxAge = min(5, max(0, resolution.maxAge ?? 5))
                return (value: resolution.endpoints, expiresAt: Date().addingTimeInterval(maxAge))
            }
            return endpoints?.compactMap(URL.init(string:)).first { endpoint in
                endpoint != failed && endpoint.host != nil && endpoint.user == nil && endpoint.password == nil
                    && endpoint.query == nil && endpoint.fragment == nil
                    && (endpoint.scheme == "https" || (failed.scheme == "http" && endpoint.scheme == "http"))
                    && endpoint.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    != failed.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            Logger.current.debug("Could not resolve an alternative cache endpoint; preserving the original read failure")
            return nil
        }
    }
}
