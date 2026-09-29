import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Mockable
import TuistHTTP

/// Refreshes the token pair issued by the OAuth authorization server, such as the one the
/// Tuist app obtains when signing in through the browser. Those tokens can only be refreshed
/// through the `refresh_token` grant of `/oauth2/token`; `/api/auth/refresh_token` rejects them.
@Mockable
public protocol RefreshOAuthTokenServicing: Sendable {
    func refreshTokens(
        serverURL: URL,
        refreshToken: String
    ) async throws -> ServerAuthenticationTokens
}

public struct RefreshOAuthTokenService: RefreshOAuthTokenServicing {
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let perform: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init() {
        self.init(
            serverEnvironmentService: ServerEnvironmentService(),
            perform: { try await URLSession.shared.data(for: $0) }
        )
    }

    init(
        serverEnvironmentService: ServerEnvironmentServicing,
        perform: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) {
        self.serverEnvironmentService = serverEnvironmentService
        self.perform = perform
    }

    public func refreshTokens(
        serverURL: URL,
        refreshToken: String
    ) async throws -> ServerAuthenticationTokens {
        var request = URLRequest(url: serverURL.appendingPathComponent("oauth2").appendingPathComponent("token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.addRequestIDHeader()
        ClientFeatureFlags.addHeader(to: &request)

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: serverEnvironmentService.oauthClientId()),
        ]
        request.httpBody = body.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .data(using: .utf8)

        let (data, response) = try await perform(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RefreshAuthTokenServiceError.unknownError(0)
        }

        switch httpResponse.statusCode {
        case 200:
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw RefreshAuthTokenServiceError.unknownError(httpResponse.statusCode)
            }
            // The authorization server answers 200 without a token pair when it can no longer mint tokens
            // for the grant's subject, for example once the user has been deleted.
            guard let accessToken = json["access_token"] as? String,
                  let refreshToken = json["refresh_token"] as? String
            else {
                throw RefreshAuthTokenServiceError.unauthorized("The refresh token is expired or invalid")
            }
            return ServerAuthenticationTokens(accessToken: accessToken, refreshToken: refreshToken)
        case 400, 401:
            let error = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let errorCode = error?["error"] as? String
            let errorDescription = error?["error_description"] as? String
            if httpResponse.statusCode == 401 || errorCode == "invalid_grant" {
                throw RefreshAuthTokenServiceError.unauthorized(
                    errorDescription ?? "The refresh token is expired or invalid"
                )
            }
            throw RefreshAuthTokenServiceError.badRequest
        default:
            throw RefreshAuthTokenServiceError.unknownError(httpResponse.statusCode)
        }
    }
}
