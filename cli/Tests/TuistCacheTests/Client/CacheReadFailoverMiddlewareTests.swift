import Foundation
import HTTPTypes
import Mockable
import OpenAPIRuntime
import Testing
import TuistServer

@testable import TuistCache

struct CacheReadFailoverMiddlewareTests {
    private let origin = URL(string: "https://near.kura.example.com")!
    private let alternative = URL(string: "https://far.kura.example.com")!
    private let server = URL(string: "https://tuist.example.com")!
    private let endpoints = MockGetCacheEndpointsServicing()

    private func subject(handle: String? = "acme/app") -> CacheReadFailoverMiddleware {
        CacheReadFailoverMiddleware(
            authenticationURL: server, fullHandle: handle, endpointsService: endpoints,
            resolutions: CachedValueStore(backend: .inSystemProcess)
        )
    }

    private func resolve(_ urls: [URL]) {
        given(endpoints)
            .getCacheEndpoints(serverURL: .value(server), accountHandle: .value("acme"))
            .willReturn(CacheEndpointsResolution(endpoints: urls.map(\.absoluteString), maxAge: 3600))
    }

    @Test(arguments: [502, 503, 504])
    func retries_failed_reads_at_one_other_account_endpoint(status: Int) async throws {
        resolve([origin, alternative])
        var visited: [URL] = []
        let response = try await subject().intercept(
            HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/api/cache/item"),
            body: nil, baseURL: origin, operationID: "read"
        ) { request, body, url in
            visited.append(url)
            #expect(request.path == "/api/cache/item")
            #expect(body == nil)
            return (HTTPResponse(status: .init(code: url == origin ? status : 200)), nil)
        }
        #expect(response.0.status.code == 200)
        #expect(visited == [origin, alternative])
    }

    @Test func switches_after_a_transport_timeout() async throws {
        resolve([origin, alternative])
        var visited: [URL] = []
        let response = try await subject().intercept(
            HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/"),
            body: nil, baseURL: origin, operationID: "read"
        ) { _, _, url in
            visited.append(url)
            if url == origin { throw URLError(.timedOut) }
            return (HTTPResponse(status: 200), nil)
        }
        #expect(response.0.status.code == 200)
        #expect(visited == [origin, alternative])
    }

    @Test(arguments: [200, 400, 401, 403, 404, 409, 429, 500])
    func does_not_mask_non_availability_responses(status: Int) async throws {
        let response = try await subject().intercept(
            HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/"),
            body: nil, baseURL: origin, operationID: "read"
        ) { _, _, _ in (HTTPResponse(status: .init(code: status)), nil) }
        #expect(response.0.status.code == status)
        verify(endpoints).getCacheEndpoints(serverURL: .any, accountHandle: .any).called(0)
    }

    @Test func never_replays_writes_ranges_or_unscoped_requests() async throws {
        for (method, range, handle) in [
            (HTTPRequest.Method.post, false, "acme/app" as String?),
            (.get, true, "acme/app"), (.get, false, nil), (.get, false, "acme/"),
        ] {
            var request = HTTPRequest(method: method, scheme: nil, authority: nil, path: "/")
            if range { request.headerFields[.range] = "bytes=100-" }
            var attempts = 0
            _ = try await subject(handle: handle).intercept(
                request, body: nil, baseURL: origin, operationID: "read"
            ) { _, _, _ in
                attempts += 1
                return (HTTPResponse(status: 503), nil)
            }
            #expect(attempts == 1)
        }
        verify(endpoints).getCacheEndpoints(serverURL: .any, accountHandle: .any).called(0)
    }

    @Test func preserves_the_failure_when_discovery_fails() async throws {
        given(endpoints).getCacheEndpoints(serverURL: .any, accountHandle: .any)
            .willThrow(URLError(.cannotConnectToHost))
        let response = try await subject().intercept(
            HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/"),
            body: nil, baseURL: origin, operationID: "read"
        ) { _, _, _ in (HTTPResponse(status: 503), HTTPBody("original")) }
        #expect(response.0.status.code == 503)
        #expect(try await String(collecting: #require(response.1), upTo: 100) == "original")
    }

    @Test func does_not_replay_bodies_or_authorization_throttles() async throws {
        for hasBody in [true, false] {
            var attempts = 0
            _ = try await subject().intercept(
                HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/"),
                body: hasBody ? HTTPBody("payload") : nil, baseURL: origin, operationID: "read"
            ) { _, _, _ in
                attempts += 1
                var response = HTTPResponse(status: 503)
                if !hasBody {
                    response.headerFields[HTTPField.Name("x-tuist-throttle-reason")!] = "authorization"
                }
                return (response, nil)
            }
            #expect(attempts == 1)
        }
        verify(endpoints).getCacheEndpoints(serverURL: .any, accountHandle: .any).called(0)
    }

    @Test func authenticates_each_endpoint_without_forwarding_mutated_headers() async throws {
        resolve([origin, alternative])
        let authentication = MockServerAuthenticationControlling()
        let tokens = MockCacheTokenStoring()
        given(authentication).authenticationToken(serverURL: .value(server)).willReturn(.project("session"))
        given(tokens).cacheToken(authenticationURL: .value(server), fullHandle: .value("acme/app"))
            .willReturn("scoped")
        let auth = CacheClientAuthenticationMiddleware(
            authenticationURL: server, serverAuthenticationController: authentication,
            cacheTokenStore: tokens, fullHandle: "acme/app"
        )
        var visited: [URL] = []
        let response = try await subject().intercept(
            HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/"),
            body: nil, baseURL: origin, operationID: "read"
        ) { request, body, url in
            #expect(request.headerFields[.authorization] == nil)
            return try await auth.intercept(request, body: body, baseURL: url, operationID: "read") { request, _, url in
                visited.append(url)
                #expect(request.headerFields.filter { $0.name == .authorization }.count == 1)
                #expect(request.headerFields[.authorization] == "Bearer scoped")
                return (HTTPResponse(status: url == origin ? 503 : 200), nil)
            }
        }
        #expect(response.0.status.code == 200)
        #expect(visited == [origin, alternative])
        verify(authentication).authenticationToken(serverURL: .value(server)).called(2)
        verify(tokens).cacheToken(authenticationURL: .value(server), fullHandle: .value("acme/app")).called(2)
    }

    @Test func does_not_downgrade_tls_or_retry_the_same_origin() async throws {
        resolve([URL(string: origin.absoluteString + "/")!, URL(string: "http://far.kura.example.com")!])
        var attempts = 0
        _ = try await subject().intercept(
            HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/"),
            body: nil, baseURL: origin, operationID: "read"
        ) { _, _, _ in
            attempts += 1
            return (HTTPResponse(status: 503), nil)
        }
        #expect(attempts == 1)
    }

    @Test func stops_after_one_alternative_and_shares_discovery_between_reads() async throws {
        resolve([origin, alternative, URL(string: "https://third.kura.example.com")!])
        let middleware = subject()
        var visited: [URL] = []
        for _ in 0 ..< 2 {
            _ = try await middleware.intercept(
                HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/"),
                body: nil, baseURL: origin, operationID: "read"
            ) { _, _, url in
                visited.append(url)
                return (HTTPResponse(status: 503), nil)
            }
        }
        #expect(visited == [origin, alternative, origin, alternative])
        verify(endpoints).getCacheEndpoints(serverURL: .any, accountHandle: .any).called(1)
    }

    @Test func does_not_retry_cancellation_or_tls_errors() async throws {
        for code in [URLError.Code.cancelled, .serverCertificateUntrusted] {
            await #expect(throws: URLError(code)) {
                _ = try await subject().intercept(
                    HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/"),
                    body: nil, baseURL: origin, operationID: "read"
                ) { _, _, _ in throw URLError(code) }
            }
        }
        verify(endpoints).getCacheEndpoints(serverURL: .any, accountHandle: .any).called(0)
    }
}
