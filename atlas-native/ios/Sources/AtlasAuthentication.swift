import AuthenticationServices
import Foundation
import SwiftUI

enum AtlasLoginProvider: String {
    case google
}

@MainActor
final class AtlasAuthentication: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var server: URL?
    @Published private(set) var busy = false
    @Published var errorMessage: String?
    @Published var selfHostedAddress = UserDefaults.standard.string(forKey: "atlas.selfHostedServer") ?? ""

    private var browser: ASWebAuthenticationSession?
    private var apiWaiters: [CheckedContinuation<Void, Never>] = []
    private var accountModel: AtlasAIAccounts?
    private var connectionsModel: AtlasConnections?
    private var presenceModel: AtlasPresence?
    #if os(iOS)
    @Published private(set) var sharedItems: AtlasSharedItems?
    #endif
    private(set) var sessionIdentity = UUID()
    let pushNotifications = AtlasPushNotifications()

    var environmentRequest: AtlasEnvironmentRequest { authenticatedRequest(operation: "environment") }

    #if os(macOS)
    private var workstationModel: AtlasWorkstation?
    var workstation: AtlasWorkstation? {
        guard let server else { return nil }
        if let workstationModel { return workstationModel }
        let model = AtlasWorkstation(origin: server, request: environmentRequest, live: liveRequest(operation: "environment"))
        workstationModel = model
        return model
    }
    #endif
    #if os(iOS)
    let liveActivity = AtlasOrbitLiveActivity()
    #endif

    var pushRequest: ([String: Any]) async throws -> Data {
        authenticatedRequest(operation: "push")
    }

    var liveActivityRequest: ([String: Any]) async throws -> Data {
        authenticatedRequest(operation: "orbit_activity")
    }

    var presence: AtlasPresence {
        if let presenceModel { return presenceModel }
        let model = AtlasPresence(request: liveRequest(operation: "presence"))
        presenceModel = model
        return model
    }

    var accountSettings: AtlasAIAccounts {
        if let accountModel { return accountModel }
        let identity = sessionIdentity
        let model = AtlasAIAccounts { [weak self] action in
            guard let self, self.server != nil, self.sessionIdentity == identity else {
                throw AtlasAuthenticationError(kind: "sign_in_required", message: "Sign in to Atlas again.")
            }
            return try await self.aiAccounts(action)
        }
        model.cachedRequest = AtlasReadCache.scoped(cachedRead, operation: "ai_accounts")
        accountModel = model
        return model
    }

    var connectionSettings: AtlasConnections {
        if let connectionsModel { return connectionsModel }
        let identity = sessionIdentity
        let model = AtlasConnections(request: authenticatedRequest(operation: "connections")) { [weak self] url in
            guard let self, self.server != nil, self.sessionIdentity == identity, self.browser == nil else {
                throw CancellationError()
            }
            defer { self.browser = nil }
            let callback = try await self.authenticate(url)
            guard self.sessionIdentity == identity else { throw CancellationError() }
            return callback
        }
        model.cachedRequest = AtlasReadCache.scoped(cachedRead, operation: "connections")
        connectionsModel = model
        return model
    }

    func restore() async {
        guard !busy, server == nil else { return }
        let identity = sessionIdentity
        busy = true
        defer { releaseAPI() }
        do {
            guard let session = try AtlasSecureStorage.load("session") else { return }
            let local = try await AtlasAuthBridge.command(["operation": "bootstrap", "session": try AtlasAuthBridge.object(session)])
            guard sessionIdentity == identity else { return }
            // Persist the namespace before rendering; protected requests still wait for rotation.
            try accept(local)
            let restored = try await AtlasAuthBridge.command(["operation": "restore", "session": local])
            guard sessionIdentity == identity else { return }
            try accept(restored)
        } catch {
            guard sessionIdentity == identity else { return }
            if let failure = error as? AtlasAuthenticationError, failure.kind == "rejected" {
                do {
                    try await discardSession(removeRegistration: true)
                } catch { errorMessage = error.localizedDescription }
            }
            errorMessage = error.localizedDescription
        }
    }

    func signIn(selfHosted: Bool = false, provider: AtlasLoginProvider? = nil) async {
        guard !busy, server == nil else { return }
        busy = true
        errorMessage = nil
        defer { busy = false; browser = nil }
        do {
            try AtlasSecureStorage.delete("automation.admission")
            #if os(iOS)
            try AtlasSecureStorage.delete("share.recipient")
            try? AtlasShareInbox.shared().configure(nil)
            #endif
            let address = selfHosted ? selfHostedAddress : "https://atlas.tuist.dev"
            var request: [String: Any] = ["operation": "begin", "server": address]
            if let provider { request["provider"] = provider.rawValue }
            if let saved = try AtlasSecureStorage.load("registration") { request["registration"] = try AtlasAuthBridge.object(saved) }
            let login = try await AtlasAuthBridge.command(request)
            guard let authorizationURL = login["authorization_url"] as? String,
                  let url = URL(string: authorizationURL), let pending = login["pending"],
                  let registration = login["registration"] else { throw AtlasAuthBridge.invalidResponse() }
            try AtlasSecureStorage.save("registration", value: try AtlasAuthBridge.json(registration))
            if selfHosted { UserDefaults.standard.set(address, forKey: "atlas.selfHostedServer") }
            guard let callback = try await authenticate(url) else { return }
            let session = try await AtlasAuthBridge.command([
                "operation": "complete", "pending": pending, "callback": callback.absoluteString
            ])
            try accept(session)
        } catch {
            if let failure = error as? AtlasAuthenticationError, failure.kind == "rejected" {
                do { try AtlasSecureStorage.delete("registration") } catch { errorMessage = error.localizedDescription }
            }
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        Task {
            #if os(macOS)
            await workstationModel?.signOut()
            #endif
            await presenceModel?.stop()
            await accountModel?.cancelLogin()
            await pushNotifications.signOut()
            #if os(iOS)
            await liveActivity.signOut()
            #endif
            await acquireAPI()
            defer { releaseAPI() }
            do {
                try await discardSession()
                errorMessage = nil
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func discardSession(removeRegistration: Bool = false) async throws {
        var cleanupError: Error?
        func attempt(_ cleanup: () throws -> Void) {
            do { try cleanup() } catch { if cleanupError == nil { cleanupError = error } }
        }
        var origin = server?.absoluteString
        sessionIdentity = UUID()
        server = nil
        accountModel?.invalidate()
        accountModel = nil
        let savedSession = (try? AtlasSecureStorage.load("session")).flatMap { try? AtlasAuthBridge.object($0) }
        if let session = savedSession {
            origin = (session["registration"] as? [String: Any])?["server"] as? String ?? origin
        }
        pushNotifications.prepareForSessionEnd(origin: origin)
        #if os(macOS)
        workstationModel?.invalidate()
        workstationModel = nil
        #endif
        #if os(iOS)
        liveActivity.invalidate()
        if let inbox = try? AtlasShareInbox.shared() { attempt { try inbox.configure(nil) } }
        attempt { try AtlasSecureStorage.delete("share.recipient") }
        sharedItems?.invalidate()
        sharedItems = nil
        #endif
        attempt { try AtlasSecureStorage.delete("automation.admission") }
        attempt { try AtlasSecureStorage.delete("session") }
        presenceModel?.setActive(false)
        presenceModel = nil
        connectionsModel?.invalidate()
        connectionsModel = nil
        browser?.cancel()
        browser = nil
        accountModel = nil
        if removeRegistration { attempt { try AtlasSecureStorage.delete("registration") } }
        // All current-session state is cleared before suspending, so a new login
        // cannot be removed by this old session's asynchronous cache cleanup.
        if let session = savedSession {
            _ = try? await AtlasAuthBridge.command([
                "operation": "forget_cache", "session": session, "directory": AtlasSecureStorage.readCacheURL.path
            ])
        }
        if let cleanupError { throw cleanupError }
    }

    private func acquireAPI() async {
        if busy {
            await withCheckedContinuation { apiWaiters.append($0) }
        } else {
            busy = true
        }
    }

    private func releaseAPI() {
        if apiWaiters.isEmpty { busy = false } else { apiWaiters.removeFirst().resume() }
    }

    func aiAccounts(_ action: [String: Any]) async throws -> Data {
        let identity = sessionIdentity
        await acquireAPI()
        defer { releaseAPI() }
        try Task.checkCancellation()
        guard sessionIdentity == identity else { throw CancellationError() }
        guard let saved = try AtlasSecureStorage.load("session") else {
            throw AtlasAuthenticationError(kind: "sign_in_required", message: "Sign in to Atlas again.")
        }
        do {
            let restored = try await AtlasAuthBridge.command(["operation": "restore", "session": try AtlasAuthBridge.object(saved)])
            guard sessionIdentity == identity else { throw CancellationError() }
            // Persist rotation before the API call, including when that call fails.
            try accept(restored)
            try Task.checkCancellation()
            let response = try await protectedCommand(operation: "ai_accounts", action: action, session: restored)
            guard sessionIdentity == identity else { throw CancellationError() }
            return try JSONSerialization.data(withJSONObject: response)
        } catch let failure as AtlasAuthenticationError where failure.kind == "rejected" && sessionIdentity == identity {
            errorMessage = failure.message
            do { try await discardSession(removeRegistration: true) } catch { errorMessage = error.localizedDescription }
            throw failure
        } catch {
            guard sessionIdentity == identity else { throw CancellationError() }
            throw error
        }
    }

    var holidayRequest: ([String: Any]) async throws -> Data {
        authenticatedRequest(operation: "time_off")
    }

    var businessRequest: ([String: Any]) async throws -> Data {
        authenticatedRequest(operation: "business")
    }

    var orbitRequest: ([String: Any]) async throws -> Data {
        authenticatedRequest(operation: "orbit_session")
    }

    var orbitLocalRequest: ([String: Any]) async throws -> Data {
        liveRequest(operation: "orbit_session")
    }
}

extension AtlasAuthentication {
    func apiSession(identity: UUID) async throws -> [String: Any] {
        await acquireAPI()
        defer { releaseAPI() }
        try Task.checkCancellation()
        guard sessionIdentity == identity, server != nil,
              let saved = try AtlasSecureStorage.load("session") else { throw CancellationError() }
        do {
            let restored = try await AtlasAuthBridge.command(["operation": "restore", "session": try AtlasAuthBridge.object(saved)])
            guard sessionIdentity == identity else { throw CancellationError() }
            try accept(restored)
            return restored
        } catch let failure as AtlasAuthenticationError where failure.kind == "rejected" && sessionIdentity == identity {
            try await discardSession(removeRegistration: true)
            throw failure
        }
    }

    func native(_ request: [String: Any]) async throws -> [String: Any] {
        let identity = sessionIdentity
        let session = try await apiSession(identity: identity)
        try checkSession(identity)
        do {
            let response = try await protectedCommand(operation: "native", action: request, session: session)
            try checkSession(identity)
            return response
        } catch {
            try checkSession(identity)
            throw error
        }
    }

    func pendingLaunch() throws -> [String: Any]? {
        try AtlasSecureStorage.load("automation.admission").map { try AtlasAuthBridge.object($0) }
    }

    func launch(_ request: [String: Any]) async throws -> [String: Any] {
        if let pending = try pendingLaunch() {
            guard NSDictionary(dictionary: pending).isEqual(to: request) else {
                throw AtlasAuthenticationError(kind: "pending_launch",
                                               message: "Retry your pending launch before starting another workflow.")
            }
        } else {
            try AtlasSecureStorage.save("automation.admission", value: try AtlasAuthBridge.json(request))
        }
        let response: [String: Any]
        do { response = try await native(request) } catch {
            if let failure = error as? AtlasAuthenticationError,
               ["revision_changed", "invalid_input"].contains(failure.kind) {
                try AtlasSecureStorage.delete("automation.admission")
            }
            throw error
        }
        try AtlasSecureStorage.delete("automation.admission")
        return response
    }

    private func checkSession(_ identity: UUID) throws {
        try Task.checkCancellation()
        guard sessionIdentity == identity, server != nil else { throw CancellationError() }
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

    private func accept(_ session: [String: Any]) throws {
        guard let registration = session["registration"] as? [String: Any],
              let address = registration["server"] as? String, let url = URL(string: address) else {
            throw AtlasAuthBridge.invalidResponse()
        }
        try AtlasSecureStorage.save("session", value: try AtlasAuthBridge.json(session))
        server = url
        #if os(iOS)
        if sharedItems == nil {
            do {
                let nonce = try AtlasSecureStorage.load("share.recipient").flatMap(UUID.init(uuidString:)) ?? UUID()
                try AtlasSecureStorage.save("share.recipient", value: nonce.uuidString)
                let recipient = AtlasShareRecipient(id: nonce, server: url)
                let inbox = try AtlasShareInbox.shared()
                try inbox.configure(recipient)
                let model = AtlasSharedItems(inbox: inbox, recipient: recipient,
                                             request: authenticatedRequest(operation: "moodboard"))
                sharedItems = model
                model.reload()
            } catch {
                errorMessage = "Sharing is unavailable on this installation. Your Atlas session is still available."
            }
        }
        #endif
    }
}
