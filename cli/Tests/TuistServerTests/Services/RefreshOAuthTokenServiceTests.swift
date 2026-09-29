import Foundation
import Mockable
import Testing
import TuistTesting

@testable import TuistServer

struct RefreshOAuthTokenServiceTests {
    private let serverURL = URL(string: "https://tuist.dev")!
    private let serverEnvironmentService = MockServerEnvironmentServicing()

    init() {
        given(serverEnvironmentService).oauthClientId().willReturn("client-id")
    }

    @Test(.withMockedEnvironment()) func refreshTokens_uses_the_oauth_refresh_token_grant() async throws {
        // Given
        let requests = RequestRecorder()
        let subject = RefreshOAuthTokenService(serverEnvironmentService: serverEnvironmentService) { request in
            requests.record(request)
            return Self.response(
                statusCode: 200,
                json: ["access_token": "new-access-token", "refresh_token": "new-refresh-token"]
            )
        }

        // When
        let got = try await subject.refreshTokens(serverURL: serverURL, refreshToken: "refresh-token")

        // Then
        #expect(got.accessToken == "new-access-token")
        #expect(got.refreshToken == "new-refresh-token")
        let request = try #require(requests.requests.first)
        #expect(request.url?.absoluteString == "https://tuist.dev/oauth2/token")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(
            Set(body.components(separatedBy: "&")) ==
                ["grant_type=refresh_token", "refresh_token=refresh-token", "client_id=client-id"]
        )
    }

    @Test(.withMockedEnvironment()) func refreshTokens_maps_invalid_grant_to_unauthorized() async throws {
        let subject = RefreshOAuthTokenService(serverEnvironmentService: serverEnvironmentService) { _ in
            Self.response(
                statusCode: 400,
                json: ["error": "invalid_grant", "error_description": "Given refresh token is invalid, revoked, or expired."]
            )
        }

        await #expect(throws: RefreshAuthTokenServiceError.unauthorized("Given refresh token is invalid, revoked, or expired.")) {
            try await subject.refreshTokens(serverURL: serverURL, refreshToken: "refresh-token")
        }
    }

    @Test(.withMockedEnvironment()) func refreshTokens_maps_unauthorized_client_to_unauthorized() async throws {
        let subject = RefreshOAuthTokenService(serverEnvironmentService: serverEnvironmentService) { _ in
            Self.response(statusCode: 401, json: ["error": "invalid_client", "error_description": "Invalid client."])
        }

        await #expect(throws: RefreshAuthTokenServiceError.unauthorized("Invalid client.")) {
            try await subject.refreshTokens(serverURL: serverURL, refreshToken: "refresh-token")
        }
    }

    @Test(.withMockedEnvironment()) func refreshTokens_maps_other_bad_requests_to_bad_request() async throws {
        let subject = RefreshOAuthTokenService(serverEnvironmentService: serverEnvironmentService) { _ in
            Self.response(statusCode: 400, json: ["error": "invalid_request"])
        }

        await #expect(throws: RefreshAuthTokenServiceError.badRequest) {
            try await subject.refreshTokens(serverURL: serverURL, refreshToken: "refresh-token")
        }
    }

    @Test(.withMockedEnvironment()) func refreshTokens_reports_server_errors_as_transient() async throws {
        let subject = RefreshOAuthTokenService(serverEnvironmentService: serverEnvironmentService) { _ in
            Self.response(statusCode: 503, json: [:])
        }

        do {
            _ = try await subject.refreshTokens(serverURL: serverURL, refreshToken: "refresh-token")
            Issue.record("Expected the refresh to fail")
        } catch {
            #expect(error as? RefreshAuthTokenServiceError == .unknownError(503))
            #expect(ServerErrorClassifier.isTransient(error))
        }
    }

    private static func response(statusCode: Int, json: [String: String]) -> (Data, URLResponse) {
        let data = try! JSONSerialization.data(withJSONObject: json) // swiftlint:disable:this force_try
        let response = HTTPURLResponse(
            url: URL(string: "https://tuist.dev/oauth2/token")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, response)
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _requests
    }

    func record(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        _requests.append(request)
    }
}
