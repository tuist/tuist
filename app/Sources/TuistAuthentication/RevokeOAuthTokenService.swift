import Foundation
import TuistHTTP
import TuistServer

enum RevokeOAuthTokenServiceError: LocalizedError, Equatable {
    case invalidResponse
    case unexpectedStatusCode(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The token revocation returned an invalid response"
        case let .unexpectedStatusCode(statusCode):
            return "The token revocation failed with status code: \(statusCode)"
        }
    }
}

public protocol RevokeOAuthTokenServicing: Sendable {
    func revokeRefreshToken(_ refreshToken: String, serverURL: URL) async throws
}

public struct RevokeOAuthTokenService: RevokeOAuthTokenServicing {
    private let serverEnvironmentService: ServerEnvironmentServicing

    public init(serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService()) {
        self.serverEnvironmentService = serverEnvironmentService
    }

    public func revokeRefreshToken(_ refreshToken: String, serverURL: URL) async throws {
        var request = URLRequest(url: serverURL.appending(path: "oauth2/revoke"))
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.addRequestIDHeader()
        ClientFeatureFlags.addHeader(to: &request)

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "token", value: refreshToken),
            URLQueryItem(name: "token_type_hint", value: "refresh_token"),
            URLQueryItem(name: "client_id", value: serverEnvironmentService.oauthClientId()),
        ]
        request.httpBody = body.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .data(using: .utf8)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RevokeOAuthTokenServiceError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw RevokeOAuthTokenServiceError.unexpectedStatusCode(httpResponse.statusCode)
        }
    }
}
