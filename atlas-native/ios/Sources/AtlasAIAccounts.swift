import Foundation
import SwiftUI

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
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    init(request: @escaping Request) { self.request = request }

    func account(_ provider: String) -> AtlasAIAccount? { accounts.first { $0.provider == provider } }

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
        activeRequests += 1
        defer { activeRequests -= 1 }
        do {
            _ = try await request(["action": "connect_claude", "token": token])
            await load()
            return true
        } catch { show(error); return false }
    }

    func startChatGPT() async {
        guard !busy, login == nil else { return }
        activeRequests += 1
        let current = generation
        defer { activeRequests -= 1 }
        do {
            let data = try await request(["action": "start_chatgpt"])
            let started = try decoder.decode(AtlasDeviceLogin.self, from: data)
            if current != generation {
                _ = try await request(["action": "cancel_chatgpt", "login_id": started.id])
                return
            }
            loginDeadline = ContinuousClock().now.advanced(by: .seconds(900))
            login = started
            errorMessage = nil
        } catch { show(error) }
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
                   ["login_expired", "sign_in_required"].contains(failure.kind) {
                    login = nil
                    return
                }
            }
        }
    }

    func cancelLogin() async {
        generation += 1
        let pending = login
        login = nil
        guard let pending else { return }
        activeRequests += 1
        defer { activeRequests -= 1 }
        do {
            _ = try await request(["action": "cancel_chatgpt", "login_id": pending.id])
        } catch {
            if (error as? AtlasAuthenticationError)?.kind != "login_expired" { show(error) }
        }
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

struct AtlasSettingsView: View {
    let server: URL
    @StateObject var accounts: AtlasAIAccounts
    var signOut: () -> Void

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Server", value: server.host() ?? server.absoluteString)
            }
            Section {
                accountLink("Claude", provider: "claude") { AtlasClaudeAccountView(accounts: accounts) }
                accountLink("ChatGPT", provider: "chatgpt") { AtlasChatGPTAccountView(accounts: accounts) }
            } header: {
                Text("AI accounts")
            } footer: {
                Text("Sessions you start will use your connected account for inference. User-started sessions are not available yet.")
            }
            if let message = accounts.errorMessage {
                Section {
                    Text(message).foregroundStyle(.red)
                    Button("Try again") { Task { await accounts.load() } }
                        .disabled(accounts.busy)
                }
            }
            Section {
                Button("Sign out", role: .destructive, action: signOut)
                    .disabled(accounts.busy)
            }
        }
        .navigationTitle("Settings")
        .task { await accounts.load() }
        .refreshable { await accounts.load() }
    }

    private func accountLink<Destination: View>(
        _ title: String, provider: String, @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack {
                Text(title)
                Spacer()
                if accounts.busy && accounts.accounts.isEmpty {
                    ProgressView()
                } else {
                    Text(status(provider)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func status(_ provider: String) -> String {
        guard let account = accounts.account(provider) else { return "Not loaded" }
        return account.credentialConfigured ? "Credentials saved" : "Not connected"
    }
}

struct AtlasClaudeAccountView: View {
    @ObservedObject var accounts: AtlasAIAccounts
    @State private var token = ""
    @State private var confirmingDisconnect = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Text("Install Claude Code on your computer, then run:")
                Text("claude setup-token").font(.body.monospaced()).textSelection(.enabled)
                Text("Follow the sign-in instructions and paste the generated subscription token below. This is not an Anthropic API key.")
            }
            Section {
                SecureField("Claude token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                    .accessibilityIdentifier("claude-token")
                Button(accounts.busy ? "Saving…" : "Save connection") {
                    let value = token
                    token = ""
                    Task { if await accounts.saveClaude(value) { dismiss() } }
                }
                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || accounts.busy)
            } footer: {
                Text("Atlas encrypts your token and never displays it again. " +
                     "Saving checks its format, not live access. Subscription terms apply.")
            }
            if let message = accounts.errorMessage {
                Section { Text(message).foregroundStyle(.red) }
            }
            if accounts.account("claude")?.credentialConfigured == true {
                Section {
                    Button("Disconnect Claude", role: .destructive) { confirmingDisconnect = true }
                        .disabled(accounts.busy)
                }
            }
        }
        .navigationTitle("Claude")
        .onDisappear { token = "" }
        .confirmationDialog("Disconnect Claude?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await accounts.disconnect("claude") } }
        } message: {
            Text("Atlas will delete its saved credentials. Revoke access separately in your Claude account settings.")
        }
    }
}

struct AtlasChatGPTAccountView: View {
    @ObservedObject var accounts: AtlasAIAccounts
    @State private var confirmingDisconnect = false

    var body: some View {
        Form {
            Section {
                Text("Connect your ChatGPT subscription by authorizing Atlas on OpenAI's website. " +
                     "Atlas never asks for your OpenAI password.")
                if accounts.account("chatgpt")?.loginAvailable == true {
                    if let login = accounts.login {
                        Text(login.userCode).font(.title.monospaced()).textSelection(.enabled)
                        Link("Continue to ChatGPT", destination: login.verificationUrl)
                        Text("Enter this code only if you started this sign-in. It expires in 15 minutes.")
                        Button("Cancel sign-in", role: .cancel) { Task { await accounts.cancelLogin() } }
                    } else {
                        Button(accounts.busy ? "Starting sign-in…" : "Sign in with ChatGPT") {
                            Task { await accounts.startChatGPT() }
                        }
                        .disabled(accounts.busy)
                    }
                } else if accounts.account("chatgpt") != nil {
                    Text("ChatGPT sign-in has not been enabled by your Atlas administrator.")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Load connection status") { Task { await accounts.load() } }
                        .disabled(accounts.busy)
                }
            } footer: {
                Text("An existing connection stays in place until sign-in succeeds. Leaving this page cancels pending sign-in.")
            }
            if let message = accounts.errorMessage {
                Section { Text(message).foregroundStyle(.red) }
            }
            if accounts.account("chatgpt")?.credentialConfigured == true {
                Section {
                    Button("Disconnect ChatGPT", role: .destructive) { confirmingDisconnect = true }
                        .disabled(accounts.busy)
                }
            }
        }
        .navigationTitle("ChatGPT")
        .task(id: accounts.login?.id) { if accounts.login != nil { await accounts.poll() } }
        .onDisappear { Task { await accounts.cancelLogin() } }
        .confirmationDialog("Disconnect ChatGPT?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await accounts.disconnect("chatgpt") } }
        } message: {
            Text("Atlas will delete its saved credentials. Revoke access separately in your OpenAI account settings.")
        }
    }
}
