import Foundation
import AuthenticationServices
import CryptoKit
import Security
import TuistServer

public final class LoginViewModel: ObservableObject {
    public init() {}
    @Published var isAuthenticating = false
    @Published var authenticationError: String?
    @Published var isAuthenticated = false
    
    private var presentationContextProvider = ASWebAuthenticationPresentationContextProvider()
    private let serverURL = "http://localhost:8080"
//    private let clientId = "tuist" // You may need to configure this based on your OAuth2 server setup
//    private let clientId: String = (UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString).lowercased()
    private let clientId = "5339abf2-467c-4690-b816-17246ed149d2"
    private let redirectURI = "tuist://oauth-callback"
    
    private var codeVerifier: String?
    private var codeChallenge: String?
    
    private let serverCredentialsStore: ServerCredentialsStoring = ServerCredentialsStore()

    
    func signIn() {
        startOAuth2Flow()
    }
    
    func signInWithGitHub() {
        authenticateWithURL("https://tuist.dev/auth/github")
    }
    
    private func startOAuth2Flow() {
        guard var urlComponents = URLComponents(string: "\(serverURL)/oauth/authorize") else {
            authenticationError = "Invalid server URL"
            return
        }
        
        // Generate PKCE parameters
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        
        self.codeVerifier = verifier
        self.codeChallenge = challenge
        
        // OAuth2 authorization code flow with PKCE parameters
        urlComponents.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
//            URLQueryItem(name: "scope", value: "read write"),
            URLQueryItem(name: "state", value: generateState()),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        
        guard let authURL = urlComponents.url else {
            authenticationError = "Failed to construct authorization URL"
            return
        }
        
        authenticateWithURL(authURL.absoluteString)
    }
    
    private func generateState() -> String {
        return UUID().uuidString
    }
    
    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
    
    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }
    
    private func authenticateWithURL(_ urlString: String) {
        guard let authURL = URL(string: urlString) else {
            authenticationError = "Invalid authentication URL"
            return
        }
        
        isAuthenticating = true
        authenticationError = nil
        
        let authSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "tuist"
        ) { callbackURL, error in
            Task { @MainActor in
                self.isAuthenticating = false
                
                if let error = error {
                    if case ASWebAuthenticationSessionError.canceledLogin = error {
                        self.authenticationError = "Login was cancelled"
                    } else {
                        self.authenticationError = "Authentication failed: \(error.localizedDescription)"
                    }
                    return
                }
                
                guard let callbackURL = callbackURL else {
                    self.authenticationError = "No callback URL received"
                    return
                }
                
                self.handleAuthenticationCallback(callbackURL)
            }
        }
        
        authSession.presentationContextProvider = presentationContextProvider
        authSession.prefersEphemeralWebBrowserSession = false
        authSession.start()
    }
    
    private func handleAuthenticationCallback(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            authenticationError = "Invalid callback URL"
            return
        }
        
        if let code = queryItems.first(where: { $0.name == "code" })?.value {
            Task {
                await exchangeCodeForToken(code)
            }
        } else if let error = queryItems.first(where: { $0.name == "error" })?.value {
            authenticationError = "Authentication error: \(error)"
        } else {
            authenticationError = "Unknown authentication response"
        }
    }
    
    private func exchangeCodeForToken(_ code: String) async {
        guard let url = URL(string: "\(serverURL)/oauth/token") else {
            await MainActor.run {
                authenticationError = "Invalid token endpoint URL"
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        guard let codeVerifier = self.codeVerifier else {
            await MainActor.run {
                authenticationError = "Missing PKCE code verifier"
            }
            return
        }
        
        let parameters = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientId,
            "code_verifier": codeVerifier
        ]
        
        let body = parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        
        request.httpBody = body.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run {
                    authenticationError = "Invalid response type"
                }
                return
            }
            
            if httpResponse.statusCode == 200 {
                await handleTokenResponse(data)
            } else {
                await handleTokenError(data, statusCode: httpResponse.statusCode)
            }
            
        } catch {
            await MainActor.run {
                authenticationError = "Network error: \(error.localizedDescription)"
            }
        }
    }
    
    private func handleTokenResponse(_ data: Data) async {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let accessToken = json["access_token"] as? String {
                    let refreshToken = json["refresh_token"] as? String
                    
                        let credentials = ServerCredentials(
                            token: nil,
                            accessToken: accessToken,
                            refreshToken: refreshToken
                        )
                        try await self.serverCredentialsStore.store(credentials: ServerCredentials(token: nil, accessToken: accessToken, refreshToken: refreshToken), serverURL: URL(string: "http://localhost:8080")!)
                } else {
                    await MainActor.run {
                        authenticationError = "No access token in response"
                    }
                }
            } else {
                await MainActor.run {
                    authenticationError = "Invalid token response format"
                }
            }
        } catch {
            await MainActor.run {
                authenticationError = "Failed to parse token response: \(error.localizedDescription)"
            }
        }
    }
    
    private func handleTokenError(_ data: Data, statusCode: Int) async {
        let errorMessage: String
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? String {
            errorMessage = "OAuth2 error: \(error)"
        } else {
            errorMessage = "Token exchange failed with status: \(statusCode)"
        }
        
        await MainActor.run {
            authenticationError = errorMessage
        }
    }
}

private class ASWebAuthenticationPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        return base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
