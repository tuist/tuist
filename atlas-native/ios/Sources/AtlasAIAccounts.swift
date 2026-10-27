import Combine
import Foundation

struct AtlasAIAccount: Decodable, Identifiable {
    let provider: String
    let credentialConfigured: Bool
    let loginAvailable: Bool
    var id: String { provider }
}

struct AtlasDeviceLogin: Decodable, Identifiable {
    let loginId: String
    let userCode: String
    let verificationUrl: URL
    let interval: UInt64
    let expiresAt: String
    var id: String { loginId }
}

@MainActor
final class AtlasAIAccounts: ObservableObject {
    typealias Request = ([String: Any]) async throws -> Data
    @Published private(set) var accounts: [AtlasAIAccount] = []
    @Published private(set) var login: AtlasDeviceLogin?
    @Published private var activeRequests = 0
    var busy: Bool { activeRequests > 0 }
    @Published private(set) var errorMessage: String?
    private let request: Request
    private var generation = 0
    private var loginDeadline: ContinuousClock.Instant?
    private var cancellationId: String?
    private var errorGeneration = 0
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    init(request: @escaping Request) { self.request = request }

    func account(_ provider: String) -> AtlasAIAccount? { accounts.first { $0.provider == provider } }

    func clearError() { errorGeneration += 1; errorMessage = nil }

    func retry() async {
        if cancellationId != nil { await cancelLogin() } else { await load() }
    }

    func load() async {
        activeRequests += 1
        defer { activeRequests -= 1 }
        do {
            struct Response: Decodable { let providers: [AtlasAIAccount] }
            let data = try await request(["action": "list"])
            accounts = try decoder.decode(Response.self, from: data).providers
            errorMessage = nil
        } catch { show(error) }
    }

    func saveClaude(_ token: String) async -> Bool {
        guard !busy else { return false }
        let context = errorGeneration
        activeRequests += 1
        defer { activeRequests -= 1 }
        do {
            _ = try await request(["action": "connect_claude", "token": token])
            await load()
            return true
        } catch {
            if context == errorGeneration { show(error) }
            return false
        }
    }

    func startChatGPT() async {
        guard !busy, login == nil else { return }
        if cancellationId != nil {
            await cancelLogin()
            guard !busy, login == nil, cancellationId == nil else { return }
        }
        activeRequests += 1
        let current = generation
        let context = errorGeneration
        defer { activeRequests -= 1 }
        do {
            let data = try await request(["action": "start_chatgpt"])
            let started = try decoder.decode(AtlasDeviceLogin.self, from: data)
            if current != generation {
                await cancel(started.id)
                return
            }
            loginDeadline = ContinuousClock().now.advanced(by: .seconds(900))
            login = started
            errorMessage = nil
        } catch {
            if context == errorGeneration { show(error) }
        }
    }

    func poll() async {
        activeRequests += 1
        defer { activeRequests -= 1 }
        let current = generation
        while let pending = login, !Task.isCancelled, generation == current {
            do {
                try await Task.sleep(for: .seconds(pending.interval))
                try Task.checkCancellation()
                if let loginDeadline, ContinuousClock().now >= loginDeadline {
                    login = nil
                    errorMessage = "ChatGPT sign-in expired. Start again."
                    return
                }
                let data = try await request(["action": "poll_chatgpt", "login_id": pending.id])
                guard generation == current, !Task.isCancelled else { return }
                struct Progress: Decodable { let status: String }
                if try decoder.decode(Progress.self, from: data).status == "connected" {
                    await load()
                    login = nil
                    return
                }
                errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                guard generation == current, !Task.isCancelled else { return }
                show(error)
                if let failure = error as? AtlasAuthenticationError,
                   ["login_expired", "login_failed", "sign_in_required", "rejected"].contains(failure.kind) {
                    login = nil
                    return
                }
            }
        }
    }

    func cancelLogin() async {
        generation += 1
        let pending = login?.id ?? cancellationId
        login = nil
        guard let pending else { return }
        activeRequests += 1
        defer { activeRequests -= 1 }
        await cancel(pending)
    }

    private func cancel(_ id: String) async {
        cancellationId = id
        var failure: Error?
        do {
            _ = try await request(["action": "cancel_chatgpt", "login_id": id])
        } catch {
            if (error as? AtlasAuthenticationError)?.kind != "login_expired" { failure = error }
        }
        if failure == nil && cancellationId == id { cancellationId = nil }
        await load()
        if let failure { show(failure) }
    }

    func disconnect(_ provider: String) async {
        guard !busy else { return }
        activeRequests += 1
        defer { activeRequests -= 1 }
        if provider == "chatgpt" { await cancelLogin() }
        do {
            _ = try await request(["action": "disconnect", "provider": provider])
            await load()
        } catch { show(error) }
    }

    private func show(_ error: Error) {
        guard !(error is CancellationError) else { return }
        errorMessage = (error as? AtlasAuthenticationError)?.message ?? "Could not read the Atlas response. Try again."
    }
}
