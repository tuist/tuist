import SwiftUI

/// One of the person's AI subscriptions, as `ai_subscriptions` returns it.
struct AISubscription: Identifiable, Equatable {
    let provider: String
    let connected: Bool
    let loginAvailable: Bool
    let runsThreads: Bool
    var id: String { provider }

    init(_ json: [String: Any]) {
        provider = json["provider"] as? String ?? ""
        connected = json["connected"] as? Bool ?? false
        loginAvailable = json["login_available"] as? Bool ?? true
        runsThreads = json["runs_threads"] as? Bool ?? false
    }

    var name: String {
        switch provider {
        case "claude": "Claude"
        case "chatgpt": "ChatGPT"
        default: provider
        }
    }
}

/// A pending ChatGPT device sign-in from `start_chatgpt_login`.
private struct ChatGPTLogin: Identifiable {
    let id: String
    let userCode: String
    let verificationURL: URL
    let interval: Int
}

/// Profile's AI subscriptions, which threads run on. The list is live: it
/// follows the `ai_subscriptions` socket, so connecting or disconnecting on
/// another device or on Tuist's settings page shows here too.
struct AISubscriptionsSection: View {
    let client: AppClient
    @State private var subscriptions: [AISubscription]?
    @State private var unavailable = false
    @State private var busy: String?
    @State private var connectingClaude = false
    @State private var chatGPTLogin: ChatGPTLogin?

    var body: some View {
        Section {
            if let subscriptions {
                ForEach(subscriptions) { row($0) }
            } else if unavailable {
                Text("AI subscriptions are not available for this account.")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        } header: {
            Text("AI Subscriptions")
        } footer: {
            Text("Threads run on your ChatGPT subscription. Claude subscriptions can be saved, but Claude doesn't allow them to run Luft threads yet.")
        }
        .task { await client.live("ai_subscriptions") { await reload() } }
        .sheet(isPresented: $connectingClaude) {
            ClaudeTokenSheet(client: client) { subscriptions = $0 }
        }
        .sheet(item: $chatGPTLogin) { login in
            ChatGPTLoginSheet(client: client, login: login) { Task { await reload() } }
        }
    }

    private func row(_ subscription: AISubscription) -> some View {
        LabeledContent {
            if busy == subscription.provider {
                ProgressView()
            } else if subscription.connected {
                Button("Disconnect", role: .destructive) { Task { await disconnect(subscription) } }
            } else if subscription.loginAvailable {
                Button("Connect") { Task { await connect(subscription) } }
            } else {
                Text("Unavailable").foregroundStyle(.secondary)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: subscription.name)
                Text(subscription.connected ? "Connected" : "Not connected")
                    .font(.footnote)
                    .foregroundStyle(subscription.connected ? .green : .secondary)
            }
        }
    }

    private func reload() async {
        do {
            let data = try await client.call("ai_subscriptions")
            subscriptions = (data["subscriptions"] as? [[String: Any]] ?? []).map(AISubscription.init)
            unavailable = false
        } catch {
            if subscriptions == nil { unavailable = true }
        }
    }

    private func connect(_ subscription: AISubscription) async {
        if subscription.provider == "claude" {
            connectingClaude = true
            return
        }
        busy = subscription.provider
        defer { busy = nil }
        do {
            let data = try await client.call("start_chatgpt_login")
            guard let id = data["login_id"] as? String,
                  let code = data["user_code"] as? String,
                  let url = URL(string: data["verification_url"] as? String ?? "")
            else { return }
            chatGPTLogin = ChatGPTLogin(id: id, userCode: code, verificationURL: url, interval: data["interval"] as? Int ?? 5)
        } catch {
            client.error = error.localizedDescription
        }
    }

    private func disconnect(_ subscription: AISubscription) async {
        busy = subscription.provider
        defer { busy = nil }
        do {
            let data = try await client.call("disconnect_ai_subscription", ["provider": subscription.provider])
            subscriptions = (data["subscriptions"] as? [[String: Any]] ?? []).map(AISubscription.init)
        } catch {
            client.error = error.localizedDescription
        }
    }
}

/// Saves the token `claude setup-token` prints.
private struct ClaudeTokenSheet: View {
    let client: AppClient
    let connected: ([AISubscription]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Subscription token", text: $token)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Run `claude setup-token` in a terminal, sign in, and paste the token it prints. It is not an Anthropic API key.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Connect Claude")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button("Connect") { Task { await save() } }
                            .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 220)
        #endif
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let data = try await client.call("connect_claude", ["token": token])
            connected((data["subscriptions"] as? [[String: Any]] ?? []).map(AISubscription.init))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Shows the code the person enters at OpenAI and polls until the sign-in
/// connects, expires or is cancelled.
private struct ChatGPTLoginSheet: View {
    let client: AppClient
    let login: ChatGPTLogin
    let finished: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: login.userCode)
                        .font(.system(.title, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity)
                    Button("Copy Code") { copy(login.userCode) }
                    Button("Open OpenAI") { openURL(login.verificationURL) }
                } footer: {
                    Text("Open OpenAI, sign in with your ChatGPT account and enter this code. Luft connects as soon as you approve it.")
                }
                Section {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    } else {
                        LabeledContent("Waiting for approval") { ProgressView() }
                    }
                }
            }
            .navigationTitle("Connect ChatGPT")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Task { _ = try? await client.call("cancel_chatgpt_login", ["login_id": login.id]) }
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 300)
        #endif
        .task { await poll() }
    }

    private func poll() async {
        while !Task.isCancelled, error == nil {
            try? await Task.sleep(for: .seconds(max(login.interval, 1)))
            guard !Task.isCancelled else { return }
            do {
                let data = try await client.call("poll_chatgpt_login", ["login_id": login.id])
                switch data["status"] as? String {
                case "connected":
                    finished()
                    dismiss()
                    return
                case "failed":
                    error = String(localized: "The sign-in expired or was refused. Cancel and connect again.")
                default:
                    break
                }
            } catch {
                // Offline for a moment: keep polling.
            }
        }
    }

    private func copy(_ text: String) {
        #if os(iOS)
            UIPasteboard.general.string = text
        #else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
