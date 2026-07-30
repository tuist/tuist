import Foundation
import Mockable
import OpenAPIRuntime
import Testing
import TuistServer

@testable import TuistCache

struct CacheClientTests {
    @Test func authenticated_client_retries_legacy_service_unavailable_responses() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModuleCacheURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let authenticationAttempts = AuthenticationAttemptTracker()
        let authenticationController = MockServerAuthenticationControlling()
        given(authenticationController)
            .authenticationToken(serverURL: .any)
            .willProduce { _ in
                .project(authenticationAttempts.nextToken())
            }
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
        #expect(authenticationAttempts.count == 2)
    }

    @Test func cas_download_does_not_retry_thrown_transport_errors() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FailingCASURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let authenticationController = MockServerAuthenticationControlling()
        given(authenticationController)
            .authenticationToken(serverURL: .any)
            .willProduce { _ in .project("token") }
        let client = Client.authenticated(
            cacheURL: URL(string: "https://cache.tuist.dev")!,
            authenticationURL: URL(string: "https://tuist.dev")!,
            serverAuthenticationController: authenticationController,
            session: session,
            retriesTransportErrors: false
        )

        await #expect(throws: (any Error).self) {
            _ = try await client.downloadCASArtifact(
                .init(
                    path: .init(id: "artifact"),
                    query: .init(
                        account_handle: "account",
                        project_handle: "project"
                    )
                )
            )
        }

        #expect(FailingCASURLProtocol.attempts.count == 1)
    }
}

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    var count: Int {
        lock.withLock { _count }
    }

    func increment() {
        lock.withLock { _count += 1 }
    }
}

private final class FailingCASURLProtocol: URLProtocol {
    static let attempts = RequestCounter()

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.attempts.increment()
        client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
    }

    override func stopLoading() {}
}

private final class AuthenticationAttemptTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    var count: Int {
        lock.withLock { _count }
    }

    func nextToken() -> String {
        lock.withLock {
            _count += 1
            return _count == 1 ? "first-attempt" : "retry"
        }
    }
}

private final class ModuleCacheURLProtocol: URLProtocol {
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let isRetry = request.value(forHTTPHeaderField: "Authorization") == "Bearer retry"
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: isRetry ? 200 : 503,
            httpVersion: nil,
            headerFields: [
                "Content-Type": "application/octet-stream",
            ]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: isRetry ? Data("artifact".utf8) : Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
