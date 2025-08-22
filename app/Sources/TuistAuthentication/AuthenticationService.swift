import AuthenticationServices
import CryptoKit
import Foundation
import SwiftUI
import TuistAppStorage
import TuistServer

public enum AuthenticationError: LocalizedError {
    case invalidCallbackURL
    case missingAuthorizationCode
    case invalidTokenResponse
    case tokenExchangeFailed(statusCode: Int)
    case missingTokens
    case appleSignInFailed
    case missingAppleCredentials

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
        case .appleSignInFailed:
            return "Apple Sign In failed"
        case .missingAppleCredentials:
            return "Missing Apple credentials from authorization"
        }
    }
}

public final class AuthenticationService: ObservableObject {
    @Published public var authenticationState: AuthenticationState

    private let serverEnvironmentService: ServerEnvironmentServicing
    private let appStorage: AppStoring
    private var credentialsListenerTask: Task<Void, Never>?
    private let presentationContextProvider = ASWebAuthenticationPresentationContextProvider()
    private let redirectURI = "tuist://oauth-callback"
    private let deleteAccountService: DeleteAccountServicing

    public init(
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        appStorage: AppStoring = AppStorage(),
        deleteAccountService: DeleteAccountServicing = DeleteAccountService(),
    ) {
        self.serverEnvironmentService = serverEnvironmentService
        self.appStorage = appStorage
        self.deleteAccountService = deleteAccountService

        authenticationState = (try? appStorage.get(AuthenticationStateKey.self)) ?? .loggedOut

        startCredentialsListener()
    }

    deinit {
        credentialsListenerTask?.cancel()
    }

    private func startCredentialsListener() {
        credentialsListenerTask = Task {
            for await credentials in ServerCredentialsStore.current.credentialsChanged {
                await MainActor.run {
                    do {
                        try updateAuthenticationState(with: credentials)
                    } catch {
                        authenticationState = .loggedOut
                        try? appStorage.set(AuthenticationStateKey.self, value: .loggedOut)
                    }
                }
            }
        }
    }

    private func updateAuthenticationState(with credentials: ServerCredentials?) throws {
        if let credentials {
            let account = try extractAccount(from: credentials.accessToken)
            authenticationState = .loggedIn(account: account)
        } else {
            authenticationState = .loggedOut
        }

        try? appStorage.set(AuthenticationStateKey.self, value: authenticationState)
    }

    private func extractAccount(from accessToken: String) throws -> Account {
        let jwt = try JWT.parse(accessToken)

        guard let email = jwt.email,
              let handle = jwt.preferredUsername
        else {
            throw AuthenticationError.missingTokens
        }

        return Account(email: email, handle: handle)
    }

    public func signOut() async {
        try! await ServerCredentialsStore.current.delete(serverURL: serverEnvironmentService.url())
        await MainActor.run {
            try? updateAuthenticationState(with: nil)
        }
    }

    public func deleteAccount(_ account: Account) async throws {
        try await deleteAccountService.deleteAccount(
            handle: account.handle,
            serverURL: serverEnvironmentService.url()
        )
        await signOut()
    }

    public func signIn() async throws {
        try await startOAuth2Flow(with: "/oauth2/authorize")
    }

    public func signInWithGitHub() async throws {
        try await startOAuth2Flow(with: "/oauth2/github")
    }

    public func signInWithGoogle() async throws {
        try await startOAuth2Flow(with: "/oauth2/google")
    }

    public func signInWithApple(authorization: ASAuthorization) async throws {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = appleIDCredential.identityToken,
              let identityTokenString = String(data: identityToken, encoding: .utf8),
              let authorizationCode = appleIDCredential.authorizationCode,
              let authorizationCodeString = String(data: authorizationCode, encoding: .utf8)
        else {
            throw AuthenticationError.missingAppleCredentials
        }

        try await exchangeAppleTokenForServerToken(
            identityToken: identityTokenString,
            authorizationCode: authorizationCodeString
        )
    }

    public func signInWithEmailAndPassword(email: String, password: String) async throws {
        let url = serverEnvironmentService.url().appending(path: "api/auth")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let parameters = [
            "email": email,
            "password": password,
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: parameters)
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthenticationError.invalidTokenResponse
        }

        if httpResponse.statusCode == 200 {
            try await handleTokenResponse(data)
        } else {
            throw AuthenticationError.tokenExchangeFailed(statusCode: httpResponse.statusCode)
        }
    }

    private func exchangeAppleTokenForServerToken(
        identityToken: String,
        authorizationCode: String
    ) async throws {
        let url = serverEnvironmentService.url().appending(path: "api/auth/apple")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let parameters = [
            "identity_token": identityToken,
            "authorization_code": authorizationCode,
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: parameters)
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthenticationError.invalidTokenResponse
        }

        if httpResponse.statusCode == 200 {
            try await handleTokenResponse(data)
        } else {
            throw AuthenticationError.tokenExchangeFailed(statusCode: httpResponse.statusCode)
        }
    }

    private func startOAuth2Flow(with path: String) async throws {
        var urlComponents = URLComponents(
            url: serverEnvironmentService.url().appending(path: path),
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
                if error != nil {
                    // The error often happens here when the user just cancels the authentication. Additionally, the errors coming
                    // from the callback are cryptic.
                    // The best thing here to do UX-wise is not to show any errors.
                    continuation.resume(returning: nil)
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: AuthenticationError.invalidCallbackURL)
                    return
                }

                guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "code" })?.value
                else {
                    continuation.resume(throwing: AuthenticationError.missingAuthorizationCode)
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
        let url = serverEnvironmentService.url().appending(path: "oauth2/token")

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

        let body = parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthenticationError.invalidTokenResponse
        }

        if httpResponse.statusCode == 200 {
            try await handleTokenResponse(data)
        } else {
            throw AuthenticationError.tokenExchangeFailed(statusCode: httpResponse.statusCode)
        }
    }

    private func handleTokenResponse(_ data: Data) async throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthenticationError.invalidTokenResponse
        }

        guard let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String
        else {
            throw AuthenticationError.missingTokens
        }

        try await ServerCredentialsStore.current.store(
            credentials: ServerCredentials(
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
