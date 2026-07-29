import Foundation
import Mockable
import OpenAPIRuntime
import Testing
import TuistServer

@testable import TuistCache

struct CacheClientTests {
    @Test func authenticated_client_retries_legacy_service_unavailable_responses() async throws {
        ModuleCacheURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModuleCacheURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let authenticationController = MockServerAuthenticationControlling()
        given(authenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))
        let client = Client.authenticated(
            cacheURL: URL(string: "https://cache.tuist.dev")!,
            authenticationURL: URL(string: "https://tuist.dev")!,
            serverAuthenticationController: authenticationController,
            session: session
        )

        let response = try await client.downloadModuleCacheArtifact(
            .init(
                path: .init(id: "artifact"),
                query: .init(
                    account_handle: "account",
                    project_handle: "project",
                    hash: "hash",
                    name: "Module.framework",
                    cache_category: "builds"
                )
            )
        )

        let body = try response.ok.body.binary
        #expect(try await Data(collecting: body, upTo: .max) == Data("artifact".utf8))
        #expect(ModuleCacheURLProtocol.requestCount == 2)
    }
}

private final class ModuleCacheURLProtocol: URLProtocol {
    private nonisolated(unsafe) static let lock = NSLock()
    private nonisolated(unsafe) static var _requestCount = 0

    static var requestCount: Int {
        lock.withLock { _requestCount }
    }

    static func reset() {
        lock.withLock {
            _requestCount = 0
        }
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let attempt = Self.lock.withLock {
            Self._requestCount += 1
            return Self._requestCount
        }
        let statusCode = attempt == 1 ? 503 : 200
        let body = attempt == 1 ? Data() : Data("artifact".utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: [
                "Content-Type": "application/octet-stream",
            ]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
