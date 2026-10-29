import SwiftUI

struct AtlasSettingsView: View {
    let server: URL
    @ObservedObject var accounts: AtlasAIAccounts
    var signOut: () -> Void
    var profileRequest: (([String: Any]) async throws -> Data)?
    var notifications: AtlasPushNotifications?
    #if os(iOS)
    var sharedItems: AtlasSharedItems?
    #endif
    var connections: AtlasConnections?
    @State private var profile: AtlasNativeProfile?
    @State private var profileError: String?
    @State private var editor: AtlasProfileEditorModel?
    @State private var profileGeneration = 0
    @Environment(\.atlasPresence) private var presence
    @Environment(\.atlasReadCache) private var cachedRead
    @Environment(\.atlasEnvironmentRequest) private var environmentRequest

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
                        .disabled(profile.cached == true)
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
            #if os(iOS)
            if let sharedItems {
                Section {
                    Button { sharedItems.reload(); sharedItems.presented = true } label: {
                        Label("Shared items", systemImage: "square.and.arrow.down")
                    }.accessibilityIdentifier("profile-shared-items")
                } footer: { Text("Review items shared from other apps before adding them to Moodboard.") }
            }
            #endif
            if let notifications, profile?.pushNotifications?.supportsCurrentPlatform == true {
                AtlasPushSettingsView(notifications: notifications)
            }
            if let connections {
                Section {
                    NavigationLink {
                        AtlasConnectionsView(model: connections)
                    } label: {
                        Label("Connections", systemImage: "link")
                    }
                    .accessibilityIdentifier("profile-connections")
                }
            }
            if let environmentRequest {
                Section {
                    NavigationLink {
                        AtlasCodingSettingsView(request: environmentRequest)
                    } label: {
                        Label("Coding", systemImage: "chevron.left.forwardslash.chevron.right")
                    }.accessibilityIdentifier("profile-coding")
                }
            }
            Section {
                accountLink(.claude) { AtlasClaudeAccountView(accounts: accounts) }
                accountLink(.chatgpt) { AtlasChatGPTAccountView(accounts: accounts) }
            } header: {
                Text("AI accounts")
            } footer: {
                Text("These accounts power conversations you start with Pip.")
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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #else
        .formStyle(.grouped)
        #endif
        .toolbar {
            AtlasPresenceToolbar()
            ToolbarItem(placement: .primaryAction) { AtlasBrowserButton(screen: "profile") }
        }
        .modifier(AtlasThemedContent())
        .onAppear { presence?.show(resource: "profile") }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $editor) { editor in
            AtlasProfileEditor(model: editor) { profile = $0 }
        }
        .protectsAtlasNavigation(editor != nil)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private func load() async {
        async let metadata: Void = accounts.load()
        await loadProfile()
        await metadata
    }

    private func loadProfile() async {
        guard let profileRequest, editor == nil else { return }
        profileGeneration += 1
        let generation = profileGeneration
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if profile == nil, let data = await cachedRead?(["operation": "business", "resource": "profile", "action": "list"]),
           generation == profileGeneration, editor == nil, !Task.isCancelled {
            profile = try? decoder.decode(AtlasNativeProfile.self, from: data)
        }
        do {
            let data = try await profileRequest(["resource": "profile", "action": "list"])
            let loaded = try decoder.decode(AtlasNativeProfile.self, from: data)
            guard generation == profileGeneration, editor == nil, !Task.isCancelled else { return }
            profile = loaded
            profileError = nil
        } catch is CancellationError {} catch {
            if generation == profileGeneration, editor == nil, !Task.isCancelled {
                if AtlasReadCache.accessDenied(error) { profile = nil }
                profileError = error.localizedDescription
            }
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
    @FocusState private var editingDescription: Bool

    var body: some View {
        NavigationStack {
            Form {
                if let error = model.errorMessage { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    TextEditor(text: $model.draft)
                        .frame(minHeight: 180)
                        .focused($editingDescription)
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
                if model.saving { Section { ProgressView("Saving…") } }
            }
            .disabled(model.saving)
            .navigationTitle("Your description")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #else
            .formStyle(.grouped)
            .frame(width: 540, height: 420)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if model.dirty { discarding = true } else { dismiss() } }
                        .disabled(model.saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        editingDescription = false
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

struct AtlasPushSettingsView: View {
    @ObservedObject var notifications: AtlasPushNotifications

    var body: some View {
        Section {
            Toggle("Push notifications", isOn: Binding(
                get: { notifications.enabled },
                set: { enabled in Task { if enabled { await notifications.enable() } else { await notifications.disable() } } }
            )).disabled(notifications.busy)
            if let message = notifications.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
        } footer: {
            Text("Get notified when Pip finishes. Alerts include the thread title and a short reply preview. "
                 + "Control lock-screen previews in \(AtlasPushSystem.settingsName).")
        }
    }
}
