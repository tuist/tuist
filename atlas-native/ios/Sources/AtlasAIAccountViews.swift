import SwiftUI

private enum AtlasAIService: String {
    case claude, chatgpt

    var title: String { self == .claude ? "Claude" : "ChatGPT" }
    var symbol: String { self == .claude ? "asterisk" : "bubble.left.and.bubble.right.fill" }
    var color: Color {
        self == .claude ? Color(red: 0.76, green: 0.40, blue: 0.28) : Color(red: 0.08, green: 0.50, blue: 0.40)
    }
}

private struct AtlasServiceIcon: View {
    let service: AtlasAIService
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: service.symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(service.color)
            .frame(width: size, height: size)
            .background(service.color.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.25))
            .accessibilityHidden(true)
    }
}

private struct AtlasServiceHeader: View {
    let service: AtlasAIService
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            AtlasServiceIcon(service: service, size: 64)
            Text(title).font(.title2.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }
}

struct AtlasSettingsView: View {
    let server: URL
    @StateObject var accounts: AtlasAIAccounts
    var signOut: () -> Void

    var body: some View {
        Form {
            Section("Account") {
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .foregroundStyle(.tint)
                        .frame(width: 36, height: 36)
                        .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Atlas server")
                        Text(server.host() ?? server.absoluteString)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                accountLink(.claude) { AtlasClaudeAccountView(accounts: accounts) }
                accountLink(.chatgpt) { AtlasChatGPTAccountView(accounts: accounts) }
            } header: {
                Text("AI accounts")
            } footer: {
                Text("These accounts will power sessions you start. Sessions aren’t available yet.")
            }
            if let message = accounts.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                    Button("Try again") { Task { await accounts.load() } }.disabled(accounts.busy)
                }
            }
            Section {
                Button(role: .destructive, action: signOut) {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .tint(.red)
                .disabled(accounts.busy)
            }
        }
        .navigationTitle("Settings")
        .task { await accounts.load() }
        .refreshable { await accounts.load() }
    }

    private func accountLink<Destination: View>(
        _ service: AtlasAIService, @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                AtlasServiceIcon(service: service)
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.title).font(.body.weight(.medium))
                    HStack(spacing: 4) {
                        if accounts.account(service.rawValue)?.credentialConfigured == true {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        Text(status(service.rawValue)).foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
                Spacer()
                if accounts.busy && accounts.accounts.isEmpty { ProgressView() }
            }
            .padding(.vertical, 5)
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
                AtlasServiceHeader(
                    service: .claude,
                    title: accounts.account("claude")?.credentialConfigured == true ? "Update Claude" : "Connect Claude",
                    subtitle: "Use your Claude Code subscription."
                )
            }
            Section {
                SecureField("Paste subscription token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                    .accessibilityIdentifier("claude-token")
                    .padding(.vertical, 8)
            } header: {
                Text("Subscription token")
            } footer: {
                Text("Encrypted and never shown again. Saving checks format, not live access.")
            }
            Section {
                DisclosureGroup("How to get a token") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("On your computer, install Claude Code and run:")
                        Text("claude setup-token")
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                        Text("Follow the sign-in instructions, then paste the subscription token above. " +
                             "Use a Claude subscription token, not an Anthropic API key. Subscription terms apply.")
                        Link("Install Claude Code", destination: URL(string: "https://code.claude.com/docs/en/setup")!)
                    }
                    .font(.subheadline)
                    .padding(.vertical, 8)
                }
            }
            if let message = accounts.errorMessage {
                Section { Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
            }
            if accounts.account("claude")?.credentialConfigured == true {
                Section {
                    Button("Disconnect Claude", role: .destructive) { confirmingDisconnect = true }
                        .disabled(accounts.busy)
                }
            }
        }
        .navigationTitle("Claude")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button {
                let value = token
                token = ""
                Task { if await accounts.saveClaude(value) { dismiss() } }
            } label: {
                Text(accounts.busy ? "Saving…" : "Save connection").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || accounts.busy)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
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
                AtlasServiceHeader(service: .chatgpt, title: "Connect ChatGPT", subtitle: "Use your ChatGPT subscription.")
            }
            if let login = accounts.login {
                Section {
                    VStack(spacing: 12) {
                        Text("Your sign-in code").font(.subheadline).foregroundStyle(.secondary)
                        Text(login.userCode)
                            .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                            .textSelection(.enabled)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } footer: {
                    Text("Only use this code for a sign-in you started. Valid for 15 minutes.")
                }
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Waiting for authorization…").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Leaving this screen cancels sign-in. Your saved account stays unchanged.")
                }
            } else if accounts.account("chatgpt")?.loginAvailable == true {
                Section {
                    Label("Sign in on OpenAI’s website", systemImage: "arrow.up.right.square")
                    Label("Return here to finish connecting", systemImage: "checkmark.circle")
                } header: {
                    Text("How it works")
                } footer: {
                    Text("Atlas never asks for your OpenAI password. An existing account stays unchanged until sign-in succeeds.")
                }
            } else if accounts.account("chatgpt") != nil {
                Section {
                    Label("Sign-in unavailable", systemImage: "lock")
                    Text("Your Atlas administrator needs to enable ChatGPT sign-in.").foregroundStyle(.secondary)
                }
            }
            if let message = accounts.errorMessage {
                Section { Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
            }
            if accounts.account("chatgpt")?.credentialConfigured == true {
                Section {
                    Button("Disconnect ChatGPT", role: .destructive) { confirmingDisconnect = true }
                        .disabled(accounts.busy)
                }
            }
        }
        .navigationTitle("ChatGPT")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { actions }
        .task(id: accounts.login?.id) { if accounts.login != nil { await accounts.poll() } }
        .onDisappear { Task { await accounts.cancelLogin() } }
        .confirmationDialog("Disconnect ChatGPT?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await accounts.disconnect("chatgpt") } }
        } message: {
            Text("Atlas will delete its saved credentials. Revoke access separately in your OpenAI account settings.")
        }
    }

    @ViewBuilder private var actions: some View {
        if accounts.login != nil || accounts.account("chatgpt")?.loginAvailable == true || accounts.account("chatgpt") == nil {
            VStack(spacing: 12) {
                if let login = accounts.login {
                    Link(destination: login.verificationUrl) {
                        Label("Continue to ChatGPT", systemImage: "arrow.up.right").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Button("Cancel sign-in", role: .cancel) { Task { await accounts.cancelLogin() } }
                } else {
                    Button {
                        Task {
                            if accounts.account("chatgpt") == nil { await accounts.load() } else { await accounts.startChatGPT() }
                        }
                    } label: {
                        Text(startLabel).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(accounts.busy)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    private var startLabel: String {
        if accounts.account("chatgpt") == nil { return "Load connection status" }
        return accounts.busy ? "Starting sign-in…" : "Sign in with ChatGPT"
    }
}
