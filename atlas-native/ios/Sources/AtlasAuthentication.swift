import AtlasAuthFFI
import AuthenticationServices
import Foundation
import SwiftUI

struct AtlasAuthenticationError: LocalizedError {
    let kind: String
    let message: String
    var errorDescription: String? { message }
}

enum AtlasAuthBridge {
    static func execute(_ input: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try input.withCString { pointer in
                guard let result = atlas_auth_execute(pointer) else {
                    throw AtlasAuthenticationError(kind: "internal", message: "Could not complete sign-in.")
                }
                defer { atlas_auth_free(result) }
                return String(cString: result)
            }
        }.value
    }
}

@MainActor
final class AtlasAuthentication: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var server: URL?
    @Published private(set) var busy = false
    @Published var errorMessage: String?
    @Published var selfHostedAddress = UserDefaults.standard.string(forKey: "atlas.selfHostedServer") ?? ""

    private var browser: ASWebAuthenticationSession?

    func restore() async {
        guard !busy, server == nil else { return }
        busy = true
        defer { busy = false }
        do {
            guard let session = try AtlasSecureStorage.load("session") else { return }
            let restored = try await command(["operation": "restore", "session": try object(session)])
            try accept(restored)
        } catch {
            if let failure = error as? AtlasAuthenticationError, failure.kind == "rejected" {
                do {
                    try AtlasSecureStorage.delete("session")
                    try AtlasSecureStorage.delete("registration")
                } catch { errorMessage = error.localizedDescription }
            }
            errorMessage = error.localizedDescription
        }
    }

    func signIn(selfHosted: Bool = false) async {
        guard !busy, server == nil else { return }
        busy = true
        errorMessage = nil
        defer { busy = false; browser = nil }
        do {
            let address = selfHosted ? selfHostedAddress : "https://atlas.tuist.dev"
            var request: [String: Any] = ["operation": "begin", "server": address]
            if let saved = try AtlasSecureStorage.load("registration") { request["registration"] = try object(saved) }
            let login = try await command(request)
            guard let authorizationURL = login["authorization_url"] as? String,
                  let url = URL(string: authorizationURL), let pending = login["pending"],
                  let registration = login["registration"] else { throw invalidResponse() }
            try AtlasSecureStorage.save("registration", value: try json(registration))
            if selfHosted { UserDefaults.standard.set(address, forKey: "atlas.selfHostedServer") }
            guard let callback = try await authenticate(url) else { return }
            let session = try await command(["operation": "complete", "pending": pending, "callback": callback.absoluteString])
            try accept(session)
        } catch {
            if let failure = error as? AtlasAuthenticationError, failure.kind == "rejected" {
                do { try AtlasSecureStorage.delete("registration") } catch { errorMessage = error.localizedDescription }
            }
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        do {
            try AtlasSecureStorage.delete("session")
            server = nil
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func destination(_ url: URL) -> URL {
        guard let server, var destination = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let origin = URLComponents(url: server, resolvingAgainstBaseURL: false) else { return url }
        destination.scheme = origin.scheme
        destination.host = origin.host
        destination.port = origin.port
        return destination.url ?? url
    }

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private func authenticate(_ url: URL) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "dev.tuist.atlas") { callback, error in
                if let failure = error as? ASWebAuthenticationSessionError, failure.code == .canceledLogin {
                    continuation.resume(returning: nil)
                } else if error != nil {
                    continuation.resume(throwing: AtlasAuthenticationError(kind: "browser", message: "Could not open secure sign-in."))
                } else { continuation.resume(returning: callback) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            browser = session
            if !session.start() {
                continuation.resume(throwing: AtlasAuthenticationError(kind: "browser", message: "Could not open secure sign-in."))
            }
        }
    }

    private func command(_ value: [String: Any]) async throws -> [String: Any] {
        let input = try json(value)
        let result = try object(await AtlasAuthBridge.execute(input))
        if let failure = result["error"] as? [String: String] {
            throw AtlasAuthenticationError(kind: failure["kind"] ?? "internal", message: failure["message"] ?? "Sign-in failed.")
        }
        guard let value = result["ok"] as? [String: Any] else { throw invalidResponse() }
        return value
    }

    private func accept(_ session: [String: Any]) throws {
        guard let registration = session["registration"] as? [String: Any],
              let address = registration["server"] as? String, let url = URL(string: address) else { throw invalidResponse() }
        try AtlasSecureStorage.save("session", value: try json(session))
        server = url
    }

    private func json(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value)
        guard let value = String(data: data, encoding: .utf8) else { throw invalidResponse() }
        return value
    }

    private func object(_ value: String) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any] else { throw invalidResponse() }
        return object
    }

    private func invalidResponse() -> AtlasAuthenticationError {
        AtlasAuthenticationError(kind: "invalid_response", message: "The server returned an invalid OAuth response.")
    }
}
