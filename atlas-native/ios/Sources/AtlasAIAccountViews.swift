import SwiftUI
import UIKit

enum AtlasSettingsStyle {
    static let tint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 102 / 255, green: 199 / 255, blue: 232 / 255, alpha: 1)
            : UIColor(red: 8 / 255, green: 124 / 255, blue: 170 / 255, alpha: 1)
    })
    static let onTint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .white
    })
}

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
            Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
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
    @ObservedObject var accounts: AtlasAIAccounts
    var signOut: () -> Void

    var body: some View {
        Form {
            Section("Account") {
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .foregroundStyle(.tint)
                        .frame(width: 36, height: 36)
                        .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Atlas server")
                        Text(server.host() ?? server.absoluteString)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
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
                    Button("Try again") { Task { await accounts.retry() } }.disabled(accounts.busy)
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
        .tint(AtlasSettingsStyle.tint)
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
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
                        }
                        Text(status(service.rawValue)).foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
                Spacer()
                if accounts.busy && accounts.accounts.isEmpty { ProgressView() }
            }
            .padding(.vertical, 5)
            .accessibilityElement(children: .combine)
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
    @State private var saving = false
    @State private var visible = false
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
                    .accessibilityLabel("Claude subscription token")
                    .submitLabel(.done)
                    .onSubmit(save)
                    .disabled(saving)
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
                        Link(destination: URL(string: "https://code.claude.com/docs/en/setup")!) {
                            Text("Install Claude Code")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("claude-install-link")
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
            Button(action: save) {
                HStack {
                    if saving { ProgressView().tint(.secondary) }
                    Text(saving ? "Saving…" : "Save connection")
                }
                .frame(maxWidth: .infinity, minHeight: 24)
                .foregroundStyle(canSave ? AtlasSettingsStyle.onTint : Color.secondary)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSave)
            .frame(maxWidth: 560)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
        .tint(AtlasSettingsStyle.tint)
        .onAppear { visible = true; accounts.clearError() }
        .onDisappear { visible = false; token = ""; accounts.clearError() }
        .confirmationDialog("Disconnect Claude?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await accounts.disconnect("claude") } }
        } message: {
            Text("Atlas will delete its saved credentials. Revoke access separately in your Claude account settings.")
        }
    }

    private var canSave: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !accounts.busy && !saving
    }

    private func save() {
        guard canSave else { return }
        let value = token
        token = ""
        saving = true
        Task {
            let saved = await accounts.saveClaude(value)
            saving = false
            if saved && visible { dismiss() }
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
                            .accessibilityIdentifier("chatgpt-device-code")
                            .accessibilityLabel("Sign-in code")
                            .accessibilityValue(login.userCode.map(String.init).joined(separator: " "))
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
                Section {
                    Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                    Button("Try again") { Task { await accounts.retry() } }.disabled(accounts.busy)
                }
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
        .tint(AtlasSettingsStyle.tint)
        .task(id: accounts.login?.id) { if accounts.login != nil { await accounts.poll() } }
        .onAppear { accounts.clearError() }
        .onDisappear {
            accounts.clearError()
            Task { await accounts.cancelLogin() }
        }
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
                        Label("Continue to ChatGPT", systemImage: "arrow.up.right")
                            .frame(maxWidth: .infinity, minHeight: 24)
                            .foregroundStyle(AtlasSettingsStyle.onTint)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Button(role: .cancel) { Task { await accounts.cancelLogin() } } label: {
                        Text("Cancel sign-in")
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                } else {
                    Button {
                        Task {
                            if accounts.account("chatgpt") == nil { await accounts.load() } else { await accounts.startChatGPT() }
                        }
                    } label: {
                        HStack {
                            if accounts.busy { ProgressView() }
                            Text(startLabel)
                        }
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .foregroundStyle(accounts.busy ? Color.secondary : AtlasSettingsStyle.onTint)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(accounts.busy)
                }
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    private var startLabel: String {
        if accounts.account("chatgpt") == nil { return "Load connection status" }
        return accounts.busy ? "Please wait…" : "Sign in with ChatGPT"
    }
}
