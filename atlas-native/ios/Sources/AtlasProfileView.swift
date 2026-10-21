import SwiftUI

struct AtlasSettingsView: View {
    let server: URL
    @ObservedObject var accounts: AtlasAIAccounts
    var signOut: () -> Void
    var profileRequest: (([String: Any]) async throws -> Data)?
    @State private var profile: AtlasNativeProfile?
    @State private var profileError: String?
    @Environment(\.atlasPresence) private var presence

    var body: some View {
        Form {
            if profileRequest != nil {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 80)).foregroundStyle(.tint).accessibilityHidden(true)
                        Text(profile?.user.name ?? "Your profile").font(.headline)
                    }.frame(maxWidth: .infinity).padding(.vertical, 12)
                }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                if let profile {
                    Section { LabeledContent("Email", value: profile.user.email).textSelection(.enabled) }
                }
            }
            Section("Account") {
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .foregroundStyle(.tint)
                        .frame(width: 36, height: 36)
                        .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Atlas server")
                        Text(server.absoluteString)
                            .font(.subheadline).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                if profileRequest != nil {
                    LabeledContent("Server version", value: profile?.serverVersion ?? "Unavailable")
                    LabeledContent("App version", value: appVersion)
                }
                if let profileError {
                    Text(profileError).font(.footnote).foregroundStyle(.red)
                    Button("Retry profile") { Task { await loadProfile() } }
                }
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
            }
        }
        .navigationTitle(profileRequest == nil ? "Settings" : "Profile")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { AtlasBrowserButton(screen: "profile") } }
        .tint(AtlasSettingsStyle.tint)
        .onAppear { presence?.show(resource: "profile") }
        .task { await accounts.load(); await loadProfile() }
        .refreshable { await accounts.load(); await loadProfile() }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private func loadProfile() async {
        guard let profileRequest else { return }
        do {
            let data = try await profileRequest(["resource": "profile", "action": "list"])
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            profile = try decoder.decode(AtlasNativeProfile.self, from: data)
            profileError = nil
        } catch is CancellationError {} catch { profileError = error.localizedDescription }
    }

    private func accountLink<Destination: View>(
        _ service: AtlasAIService, @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination().onAppear { presence?.show() }
        } label: {
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
        .accessibilityIdentifier("ai-account-\(service.rawValue)")
    }

    private func status(_ provider: String) -> String {
        guard let account = accounts.account(provider) else { return "Not loaded" }
        return account.credentialConfigured ? "Credentials saved" : "Not connected"
    }
}

private struct AtlasNativeProfile: Decodable {
    struct User: Decodable {
        let name: String
        let email: String
    }
    let user: User
    let serverVersion: String
}
