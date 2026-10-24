import SwiftUI

struct AtlasSettingsView: View {
    let server: URL
    @ObservedObject var accounts: AtlasAIAccounts
    var signOut: () -> Void
    var profileRequest: (([String: Any]) async throws -> Data)?
    var notifications: AtlasPushNotifications?
    @State private var profile: AtlasNativeProfile?
    @State private var profileError: String?
    @State private var editor: AtlasProfileEditorModel?
    @State private var profileGeneration = 0
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
                    Section {
                        if !profile.user.description.isEmpty {
                            Text(profile.user.description).textSelection(.enabled)
                        }
                        Button(profile.user.description.isEmpty ? "Tell Pip about yourself" : "Edit description") {
                            if let profileRequest {
                                profileGeneration += 1
                                editor = AtlasProfileEditorModel(description: profile.user.description, request: profileRequest)
                            }
                        }
                        .accessibilityIdentifier("profile-edit-description")
                    } header: { Text("About you") } footer: {
                        Text("Share your company role, personality and communication preferences. " +
                             "Pip uses this only in your private conversations, not shared threads. " +
                             "It is sent to the configured AI provider with those conversations.")
                    }
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
                NavigationLink {
                    AtlasAppearanceView().onAppear { presence?.show() }
                } label: {
                    Label("Appearance", systemImage: "paintpalette")
                }
                .accessibilityIdentifier("profile-appearance")
            }
            if let notifications, profile?.pushNotifications?.ios == true {
                AtlasPushSettingsView(notifications: notifications)
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
        .defaultScrollAnchor(.top)
        .navigationTitle(profileRequest == nil ? "Settings" : "Profile")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            AtlasPresenceToolbar()
            ToolbarItem(placement: .topBarTrailing) { AtlasBrowserButton(screen: "profile") }
        }
        .modifier(AtlasThemedContent())
        .onAppear { presence?.show(resource: "profile") }
        .task { await accounts.load(); await loadProfile() }
        .refreshable { await accounts.load(); await loadProfile() }
        .sheet(item: $editor) { editor in
            AtlasProfileEditor(model: editor) { profile = $0 }
        }
        .protectsAtlasNavigation(editor != nil)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private func loadProfile() async {
        guard let profileRequest, editor == nil else { return }
        profileGeneration += 1
        let generation = profileGeneration
        do {
            let data = try await profileRequest(["resource": "profile", "action": "list"])
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let loaded = try decoder.decode(AtlasNativeProfile.self, from: data)
            guard generation == profileGeneration, editor == nil else { return }
            profile = loaded
            profileError = nil
        } catch is CancellationError {} catch {
            if generation == profileGeneration, editor == nil { profileError = error.localizedDescription }
        }
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

private struct AtlasProfileEditor: View {
    @ObservedObject var model: AtlasProfileEditorModel
    let saved: (AtlasNativeProfile) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var discarding = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $model.draft)
                        .frame(minHeight: 180)
                        .accessibilityLabel("About you")
                        .accessibilityIdentifier("profile-description")
                    Text("\(model.draft.unicodeScalars.count) / 4000 characters")
                        .font(.footnote).foregroundStyle(model.valid ? Color.secondary : .red)
                } header: { Text("About you") } footer: {
                    Text("For example: I lead engineering at our company. I’m curious and direct; " +
                         "I prefer concise answers with trade-offs.\n\n" +
                         "Pip uses this only in private conversations, never shared threads. " +
                         "It is sent to the configured AI provider. Avoid secrets.")
                }
                if let error = model.errorMessage { Section { Text(error).foregroundStyle(.red) } }
                if model.saving { Section { ProgressView("Saving…") } }
            }
            .disabled(model.saving)
            .navigationTitle("Your description")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if model.dirty { discarding = true } else { dismiss() } }
                        .disabled(model.saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { if let profile = await model.save() { saved(profile); dismiss() } }
                    }
                    .disabled(!model.valid || model.saving)
                    .accessibilityIdentifier("profile-save")
                }
            }
            .interactiveDismissDisabled(model.dirty || model.saving)
            .confirmationDialog("Discard changes?", isPresented: $discarding, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
            }
        }
        .protectsAtlasNavigation()
    }
}
