import AuthenticationServices
import CryptoKit
import Foundation
import TuistServer

public enum LogInViewModelError: LocalizedError {
    case invalidCallbackURL
    case missingAuthorizationCode
    case invalidTokenResponse
    case tokenExchangeFailed(statusCode: Int)
    case missingTokens

    public var errorDescription: String? {
        switch self {
        case .invalidCallbackURL:
            return "Invalid callback URL received"
        case .missingAuthorizationCode:
            return "Authorization code not found"
        case .invalidTokenResponse:
            return "Invalid response format"
        case let .tokenExchangeFailed(statusCode):
            return "Token exchange failed with status code: \(statusCode)"
        case .missingTokens:
            return "Access token or refresh token missing from response"
        }
    }
}

public final class LoginViewModel: ObservableObject {
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let serverCredentialsStore: ServerCredentialsStoring

    private let presentationContextProvider = ASWebAuthenticationPresentationContextProvider()
    private let redirectURI = "tuist://oauth-callback"

    public init(
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        serverCredentialsStore: ServerCredentialsStoring = ServerCredentialsStore()
    ) {
        self.serverEnvironmentService = serverEnvironmentService
        self.serverCredentialsStore = serverCredentialsStore
    }

    func signIn() async throws {
        try await startOAuth2Flow(with: "/oauth/authorize")
    }

    func signInWithGitHub() async throws {
        try await startOAuth2Flow(with: "/oauth/github")
    }

    func signInWithGoogle() async throws {
        try await startOAuth2Flow(with: "/oauth/google")
    }

    private func startOAuth2Flow(with path: String) async throws {
        var urlComponents = URLComponents(
            url: serverEnvironmentService.url().appending(
                path: path
            ),
            resolvingAgainstBaseURL: false
        )!

        let codeVerifier = codeVerifier()
        urlComponents.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: serverEnvironmentService.oauthClientId()),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: UUID().uuidString),
            URLQueryItem(name: "code_challenge", value: codeChallenge(from: codeVerifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        try await authenticate(
            with: urlComponents.url!,
            codeVerifier: codeVerifier
        )
    }

    private func codeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private func codeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }

    private func authenticate(
        with authURL: URL,
        codeVerifier: String
    ) async throws {
        let code: String? = try await withCheckedThrowingContinuation { continuation in
            let authSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "tuist"
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: LogInViewModelError.invalidCallbackURL)
                    return
                }

                guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "code" })?.value
                else {
                    continuation.resume(throwing: LogInViewModelError.missingAuthorizationCode)
                    return
                }

                continuation.resume(returning: code)
            }
            authSession.presentationContextProvider = presentationContextProvider
            authSession.prefersEphemeralWebBrowserSession = true
            Task {
                await MainActor.run {
                    authSession.start()
                }
            }
        }
        if let code {
            try await exchangeCodeForToken(code, codeVerifier: codeVerifier)
        }
    }

    private func exchangeCodeForToken(
        _ code: String,
        codeVerifier: String
    ) async throws {
        let url = serverEnvironmentService.url().appending(
            path: "oauth/token"
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let parameters = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": serverEnvironmentService.oauthClientId(),
            "code_verifier": codeVerifier,
        ]

        let body =
            parameters
                .map {
                    "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
                }
                .joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LogInViewModelError.invalidTokenResponse
        }

        if httpResponse.statusCode == 200 {
            try await handleTokenResponse(data)
        } else {
            throw LogInViewModelError.tokenExchangeFailed(statusCode: httpResponse.statusCode)
        }
    }

    private func handleTokenResponse(_ data: Data) async throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LogInViewModelError.invalidTokenResponse
        }

        guard let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String
        else {
            throw LogInViewModelError.missingTokens
        }

        try await serverCredentialsStore.store(
            credentials: ServerCredentials(
                token: nil,
                accessToken: accessToken,
                refreshToken: refreshToken
            ),
            serverURL: serverEnvironmentService.url()
        )
    }
}

private final class ASWebAuthenticationPresentationContextProvider: NSObject,
    ASWebAuthenticationPresentationContextProviding
{
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
}

extension Data {
    fileprivate func base64URLEncodedString() -> String {
        return base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
