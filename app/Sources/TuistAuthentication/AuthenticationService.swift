import AuthenticationServices
import CryptoKit
import Foundation
import SwiftUI
import TuistAppStorage
import TuistHTTP
import TuistLogging
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

@MainActor
public final class AuthenticationService: ObservableObject {
    @Published public var authenticationState: AuthenticationState
    @Published public private(set) var serverURL: URL

    private let serverEnvironmentService: ServerEnvironmentServicing
    private let appStorage: AppStoring
    private let credentialsStore: ServerCredentialsStoring
    private var credentialsListenerTask: Task<Void, Never>?
    private var credentialsRefreshTask: Task<Void, Never>?
    private var authenticationRefreshGeneration = 0
    private let presentationContextProvider = ASWebAuthenticationPresentationContextProvider()
    private let redirectURI = "tuist://oauth-callback"
    private let deleteAccountService: DeleteAccountServicing

    public init(
        serverEnvironmentService: ServerEnvironmentServicing? = nil,
        appStorage: AppStoring = AppStorage(),
        credentialsStore: ServerCredentialsStoring? = nil,
        deleteAccountService: DeleteAccountServicing = DeleteAccountService()
    ) {
        let serverEnvironmentService = serverEnvironmentService ?? AppServerEnvironmentService(appStorage: appStorage)
        let serverURL = serverEnvironmentService.url()
        self.serverEnvironmentService = serverEnvironmentService
        self.appStorage = appStorage
        self.credentialsStore = credentialsStore ?? ServerCredentialsStore.current
        self.deleteAccountService = deleteAccountService

        self.serverURL = serverURL
        authenticationState = Self.authenticationState(
            from: (try? appStorage.get(AuthenticationStateKey.self)) ?? .loggedOut,
            matching: serverURL
        )
        Logger.current.notice(
            "Initialized authentication service with state: \(authenticationState.logDescription)"
        )

        startCredentialsListener()
        Task {
            await refreshAuthenticationStateForActiveServer()
        }
    }

    deinit {
        credentialsListenerTask?.cancel()
        credentialsRefreshTask?.cancel()
    }

    private func startCredentialsListener() {
        let credentialsChanged = credentialsStore.credentialsChanged
        credentialsListenerTask = Task { [weak self] in
            for await credentials in credentialsChanged {
                guard let self else { return }
                Logger.current.notice(
                    "Received credentials change: hasCredentials=\(credentials != nil)"
                )
                scheduleAuthenticationRefresh()
            }
        }
    }

    private func updateAuthenticationState(
        with credentials: ServerCredentials?,
        serverURL: URL
    ) throws {
        if let credentials {
            let account = try extractAccount(from: credentials.accessToken)
            authenticationState = .loggedIn(account: account, serverURL: serverURL)
            Logger.current.notice("Authentication state updated to logged in")
        } else {
            authenticationState = .loggedOut
            Logger.current.notice("Authentication state updated to logged out")
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

    public func refreshAuthenticationStateForActiveServer() async {
        let refresh = beginAuthenticationRefresh()
        credentialsRefreshTask?.cancel()
        await performAuthenticationRefresh(
            serverURL: refresh.serverURL,
            generation: refresh.generation
        )
    }

    private func scheduleAuthenticationRefresh() {
        let refresh = beginAuthenticationRefresh()
        credentialsRefreshTask?.cancel()
        credentialsRefreshTask = Task { [weak self] in
            await self?.performAuthenticationRefresh(
                serverURL: refresh.serverURL,
                generation: refresh.generation
            )
        }
    }

    private func beginAuthenticationRefresh() -> (serverURL: URL, generation: Int) {
        authenticationRefreshGeneration += 1
        return (serverURL: serverURL, generation: authenticationRefreshGeneration)
    }

    private func performAuthenticationRefresh(
        serverURL: URL,
        generation refreshGeneration: Int
    ) async {
        do {
            let credentials = try await credentialsStore.read(serverURL: serverURL)
            guard refreshGeneration == authenticationRefreshGeneration,
                  Self.normalizedURLString(self.serverURL) == Self.normalizedURLString(serverURL)
            else {
                return
            }

            do {
                try updateAuthenticationState(with: credentials, serverURL: serverURL)
            } catch {
                authenticationState = .loggedOut
                try? appStorage.set(AuthenticationStateKey.self, value: .loggedOut)
            }
        } catch {
            guard refreshGeneration == authenticationRefreshGeneration,
                  Self.normalizedURLString(self.serverURL) == Self.normalizedURLString(serverURL)
            else {
                return
            }

            authenticationState = .loggedOut
            try? appStorage.set(AuthenticationStateKey.self, value: .loggedOut)
        }
    }

    private static func authenticationState(
        from storedAuthenticationState: AuthenticationState,
        matching serverURL: URL
    ) -> AuthenticationState {
        guard case let .loggedIn(account, storedServerURL) = storedAuthenticationState,
              normalizedURLString(storedServerURL) == normalizedURLString(serverURL)
        else {
            return .loggedOut
        }

        return .loggedIn(account: account, serverURL: serverURL)
    }

    private static func normalizedURLString(_ url: URL) -> String {
        return (try? AppServerEnvironmentService.normalizedURL(from: url.absoluteString).absoluteString) ??
            url.absoluteString
    }

    public func signOut() async {
        let serverURL = serverURL
        await signOut(serverURL: serverURL)
    }

    private func signOut(serverURL: URL) async {
        if Self.normalizedURLString(self.serverURL) == Self.normalizedURLString(serverURL) {
            authenticationRefreshGeneration += 1
            credentialsRefreshTask?.cancel()
        }
        Logger.current.notice(
            "Signing out and deleting credentials for server: \(serverURL.absoluteString)"
        )
        do {
            try await credentialsStore.delete(serverURL: serverURL)
        } catch {
            Logger.current.error(
                "Failed to delete credentials when signing out: \(error.localizedDescription)"
            )
        }

        guard Self.normalizedURLString(self.serverURL) == Self.normalizedURLString(serverURL) else {
            return
        }
        authenticationRefreshGeneration += 1
        credentialsRefreshTask?.cancel()
        try? updateAuthenticationState(with: nil, serverURL: serverURL)
    }

    public func deleteAccount(_ account: Account) async throws {
        let serverURL = serverURL
        try await deleteAccountService.deleteAccount(
            handle: account.handle,
            serverURL: serverURL
        )
        await signOut(serverURL: serverURL)
    }

    @MainActor
    public func updateServerURL(_ value: String) async throws {
        guard let serverEnvironmentService = serverEnvironmentService as? AppServerEnvironmentConfiguring else {
            throw AppServerEnvironmentServiceError.cannotChangeServerURL
        }

        let serverURL = try AppServerEnvironmentService.normalizedURL(from: value)
        try serverEnvironmentService.setCustomURL(serverURL)
        self.serverURL = serverEnvironmentService.url()
        await refreshAuthenticationStateForActiveServer()
    }

    @MainActor
    public func resetServerURL() async throws {
        guard let serverEnvironmentService = serverEnvironmentService as? AppServerEnvironmentConfiguring else {
            throw AppServerEnvironmentServiceError.cannotChangeServerURL
        }

        try serverEnvironmentService.setCustomURL(nil)
        serverURL = serverEnvironmentService.url()
        await refreshAuthenticationStateForActiveServer()
    }

    public func setPresentationAnchor(_ presentationAnchor: ASPresentationAnchor?) {
        presentationContextProvider.presentationAnchor = presentationAnchor
    }

    public var isUsingCustomServerURL: Bool {
        guard let serverEnvironmentService = serverEnvironmentService as? AppServerEnvironmentConfiguring else {
            return false
        }

        return serverEnvironmentService.customURL() != nil
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
        let serverURL = serverURL
        let url = serverURL.appending(path: "api/auth")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addRequestIDHeader()
        ClientFeatureFlags.addHeader(to: &request)

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
            try await handleTokenResponse(data, serverURL: serverURL)
        } else {
            Logger.current.error(
                """
                Email and password sign in token exchange failed with status code: \(httpResponse.statusCode), \
                requestID: \(request.requestID ?? "unknown"), \
                responseRequestID: \(httpResponse.requestID ?? "unknown")
                """
            )
            throw AuthenticationError.tokenExchangeFailed(statusCode: httpResponse.statusCode)
        }
    }

    private func exchangeAppleTokenForServerToken(
        identityToken: String,
        authorizationCode: String
    ) async throws {
        let serverURL = serverURL
        let url = serverURL.appending(path: "api/auth/apple")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addRequestIDHeader()
        ClientFeatureFlags.addHeader(to: &request)

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
            try await handleTokenResponse(data, serverURL: serverURL)
        } else {
            Logger.current.error(
                """
                Apple sign in token exchange failed with status code: \(httpResponse.statusCode), \
                requestID: \(request.requestID ?? "unknown"), \
                responseRequestID: \(httpResponse.requestID ?? "unknown")
                """
            )
            throw AuthenticationError.tokenExchangeFailed(statusCode: httpResponse.statusCode)
        }
    }

    private func startOAuth2Flow(with path: String) async throws {
        let serverURL = serverURL
        var urlComponents = URLComponents(
            url: serverURL.appending(path: path),
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
            codeVerifier: codeVerifier,
            serverURL: serverURL
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
        codeVerifier: String,
        serverURL: URL
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
            try await exchangeCodeForToken(code, codeVerifier: codeVerifier, serverURL: serverURL)
        }
    }

    private func exchangeCodeForToken(
        _ code: String,
        codeVerifier: String,
        serverURL: URL
    ) async throws {
        let url = serverURL.appending(path: "oauth2/token")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.addRequestIDHeader()
        ClientFeatureFlags.addHeader(to: &request)

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
            try await handleTokenResponse(data, serverURL: serverURL)
        } else {
            Logger.current.error(
                """
                OAuth token exchange failed with status code: \(httpResponse.statusCode), \
                requestID: \(request.requestID ?? "unknown"), \
                responseRequestID: \(httpResponse.requestID ?? "unknown")
                """
            )
            throw AuthenticationError.tokenExchangeFailed(statusCode: httpResponse.statusCode)
        }
    }

    private func handleTokenResponse(
        _ data: Data,
        serverURL: URL
    ) async throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthenticationError.invalidTokenResponse
        }

        guard let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String
        else {
            throw AuthenticationError.missingTokens
        }

        try await credentialsStore.store(
            credentials: ServerCredentials(
                accessToken: accessToken,
                refreshToken: refreshToken
            ),
            serverURL: serverURL
        )
        Logger.current.notice("Stored authentication credentials from token response")
    }
}

extension AuthenticationState {
    fileprivate var logDescription: String {
        switch self {
        case .loggedIn:
            return "loggedIn"
        case .loggedOut:
            return "loggedOut"
        }
    }
}

private final class ASWebAuthenticationPresentationContextProvider: NSObject,
    ASWebAuthenticationPresentationContextProviding
{
    weak var presentationAnchor: ASPresentationAnchor?

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return presentationAnchor ?? ASPresentationAnchor()
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
