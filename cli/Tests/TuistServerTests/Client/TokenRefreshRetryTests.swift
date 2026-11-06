import Foundation
import HTTPTypes
import Mockable
import OpenAPIRuntime
import Synchronization
import Testing
import TuistEnvironment
import TuistHTTP
import TuistTesting

@testable import TuistServer

/// Sends a request whose expired credentials are refreshed through `/api/auth/refresh_token`, with the server
/// client's retries on both the request and the refresh.
struct TokenRefreshRetryTests {
    private let serverURL = URL(string: "https://test.tuist.dev")!

    @Test(.withMockedEnvironment(), arguments: [RefreshFailure.status(502), .transport(.networkConnectionLost)])
    func sends_the_request_once_after_a_refresh_that_recovered(failure: RefreshFailure) async throws {
        let server = try RefreshingServer(refreshFailures: [failure])

        _ = try await send(through: server).ok

        #expect(server.refreshes == 2)
        #expect(server.requests == 1)
    }

    @Test(.withMockedEnvironment())
    func sends_a_failing_refresh_no_more_often_than_one_retry_layer_allows() async throws {
        let server = try RefreshingServer(refreshFailures: Array(repeating: .status(502), count: 100))

        let error = await #expect(throws: ClientError.self) {
            _ = try await send(through: server)
        }

        #expect(error?.underlyingError as? RefreshAuthTokenServiceError == .unknownError(502))
        #expect(server.refreshes == HTTPRetryPolicy().maximumRetryCount + 1)
        #expect(server.requests == 0)
    }

    private func send(through server: RefreshingServer) async throws -> Operations.listProjects.Output {
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_HTTP_RETRY_BASE_DELAY_IN_MILLISECONDS"] = "0"
        let credentials = MockServerCredentialsStoring()
        given(credentials).read(serverURL: .any).willProduce { _ in server.credentials }
        given(credentials).store(credentials: .any, serverURL: .any).willProduce { stored, _ in
            server.credentials = stored
        }
        let controller = ServerAuthenticationController(
            refreshAuthTokenService: RefreshAuthTokenService(),
            refreshOAuthTokenService: MockRefreshOAuthTokenServicing(),
            cachedValueStore: CachedValueStore(backend: .inSystemProcess)
        )
        let client = Client(
            serverURL: serverURL,
            transport: UnreachableTransport(),
            middlewares: [
                RetryMiddleware(baseDelayMilliseconds: 0),
                ServerClientAuthenticationMiddleware(serverAuthenticationController: controller),
                server,
            ]
        )
        return try await ServerCredentialsStore.$current.withValue(credentials) {
            try await Client.$additionalMiddlewares.withValue([server]) {
                try await client.listProjects(.init())
            }
        }
    }
}

enum RefreshFailure: Sendable, CustomTestStringConvertible {
    case status(Int)
    case transport(URLError.Code)

    var testDescription: String {
        switch self {
        case let .status(code): "HTTP \(code)"
        case let .transport(code): "URLError \(code.rawValue)"
        }
    }
}

/// Answers `refreshToken` with each of `refreshFailures` in turn and then with a new token pair, and every other
/// operation with an empty project list, counting both.
private final class RefreshingServer: ClientMiddleware, @unchecked Sendable {
    private let state: Mutex<(refreshFailures: [RefreshFailure], refreshes: Int, requests: Int, credentials: ServerCredentials?)>
    private let refreshedTokens: String

    init(refreshFailures: [RefreshFailure]) throws {
        let accessToken = try JWT.make(expiryDate: Date().addingTimeInterval(-100), typ: "access")
        let refreshToken = try JWT.make(expiryDate: Date().addingTimeInterval(3600), typ: "refresh")
        let newAccessToken = try JWT.make(expiryDate: Date().addingTimeInterval(3600), typ: "access")
        let newRefreshToken = try JWT.make(expiryDate: Date().addingTimeInterval(7200), typ: "refresh")
        state = Mutex((
            refreshFailures,
            0,
            0,
            .test(accessToken: accessToken.token, refreshToken: refreshToken.token)
        ))
        refreshedTokens = #"{"access_token":"\#(newAccessToken.token)","refresh_token":"\#(newRefreshToken.token)"}"#
    }

    var refreshes: Int {
        state.withLock { $0.refreshes }
    }

    var requests: Int {
        state.withLock { $0.requests }
    }

    var credentials: ServerCredentials? {
        get { state.withLock { $0.credentials } }
        set { state.withLock { $0.credentials = newValue } }
    }

    func intercept(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String,
        next _: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var response = HTTPResponse(status: .ok)
        response.headerFields[.contentType] = "application/json"
        guard operationID == "refreshToken" else {
            state.withLock { $0.requests += 1 }
            return (response, HTTPBody(#"{"projects":[]}"#))
        }
        let failure = state.withLock { state in
            state.refreshes += 1
            return state.refreshFailures.isEmpty ? nil : state.refreshFailures.removeFirst()
        }
        switch failure {
        case let .status(code):
            return (HTTPResponse(status: .init(code: code)), nil)
        case let .transport(code):
            throw URLError(code)
        case nil:
            return (response, HTTPBody(refreshedTokens))
        }
    }
}

private struct UnreachableTransport: ClientTransport {
    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        Issue.record("\(operationID) reached the transport")
        throw URLError(.cannotConnectToHost)
    }
}
