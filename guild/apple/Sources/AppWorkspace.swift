import SwiftUI

private enum Destination: Hashable {
    case threads, profile
}

struct AppWorkspace: View {
    @State private var client: AppClient
    @State private var updater: PreviewUpdater
    @State private var selection = Destination.threads
    @State private var addingProfile = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let client = AppClient()
        _client = State(initialValue: client)
        _updater = State(initialValue: PreviewUpdater(client: client))
    }

    var body: some View {
        Group {
            if client.view.active == nil {
                LogInView(client: client)
            } else {
                #if os(macOS)
                    // On the Mac, a source-list sidebar takes the place of the tab bar.
                    NavigationSplitView {
                        List(selection: $selection) {
                            Label("Threads", systemImage: "bubble.left.and.bubble.right").tag(Destination.threads)
                            Label("Profile", systemImage: "person.crop.circle").tag(Destination.profile)
                        }
                        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 280)
                    } detail: {
                        NavigationStack {
                            if selection == .profile {
                                ProfileView(client: client, updater: updater, addingProfile: $addingProfile)
                            } else {
                                ThreadsView(client: client)
                            }
                        }
                    }
                    .toolbar { ToolbarItem(placement: .primaryAction) { profilesMenu } }
                    .id(client.view.generation)
                #else
                    TabView(selection: $selection) {
                        NavigationStack { ThreadsView(client: client) }
                            .tabItem { Label("Threads", systemImage: "bubble.left.and.bubble.right") }
                            .tag(Destination.threads)
                        NavigationStack {
                            ProfileView(client: client, updater: updater, addingProfile: $addingProfile)
                                .toolbar { ToolbarItem(placement: .topBarTrailing) { profilesMenu } }
                        }
                        .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                        .tag(Destination.profile)
                    }
                    .minimizingTabBarOnScroll()
                    .id(client.view.generation)
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 520)
        #endif
        .tint(Noora.primary)
        // Omarchy themes have one appearance; system controls and bars follow it.
        .preferredColorScheme(Themes.shared.selected.appearance)
        .task { await client.perform("snapshot") }
        .task(id: client.view.active?.id) { await updater.check() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await updater.check() } }
        }
        .sheet(isPresented: $addingProfile) {
            NavigationStack {
                LogInView(client: client)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { Task { await client.cancelSignIn(); addingProfile = false } }
                        }
                    }
                    .onDisappear { Task { await client.cancelSignIn() } }
            }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 640)
            #endif
        }
        .onChange(of: client.view.generation) { _, _ in addingProfile = false }
        .alert("Something went wrong", isPresented: Binding(
            get: { client.error != nil }, set: { if !$0 { client.error = nil } }
        )) {
            Button("OK") { client.error = nil }
        } message: { Text(verbatim: client.error ?? "") }
    }

    /// Switches between saved profiles and adds new ones: in the window toolbar
    /// on the Mac, and in the Profile tab's navigation bar on iOS.
    private var profilesMenu: some View {
        Menu {
            ForEach(client.view.profiles) { profile in
                Toggle(isOn: Binding(
                    get: { profile.id == client.view.active_profile_id },
                    set: { if $0 { Task { await client.perform("switch_profile", ["id": profile.id]) } } }
                )) {
                    Text(verbatim: profile.handle ?? profile.email ?? profile.server)
                    Text(verbatim: profile.server)
                }
                .disabled(profile.rejected)
            }
            Divider()
            #if os(macOS)
                Button("Add Profile…", systemImage: "person.badge.plus") { addingProfile = true }
                Button("View Profile") { selection = .profile }
                Divider()
                Button("Sign Out") { Task { await client.perform("sign_out") } }
            #else
                Button("Add profile", systemImage: "person.badge.plus") { addingProfile = true }
            #endif
        } label: {
            Label("Profiles", systemImage: "person.2.circle")
        }
        .help("Switch profile")
    }
}

/// The shipping app's Profile page (`app/Sources/TuistProfile/ProfileView.swift`).
/// Switching and adding profiles live in the profiles menu: the Profile tab's
/// navigation bar on iOS and the window toolbar on macOS.
private struct ProfileView: View {
    let client: AppClient
    let updater: PreviewUpdater
    @Binding var addingProfile: Bool
    @State private var confirmingDelete = false

    var body: some View {
        Form {
            // Group passes the theme's row surface to every section.
            Group { sections }.listRowBackground(Noora.backgroundTertiary)
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        // Grouped rows on the theme's surfaces, like the Threads list.
        .scrollContentBackground(.hidden)
        .background(Noora.backgroundPrimary)
        .navigationTitle("Profile")
        .alert("Delete Account", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await client.perform("delete_account") } }
        } message: {
            Text("Are you sure you want to delete your account? This action cannot be undone.")
        }
    }

    @ViewBuilder private var sections: some View {
        if let account = client.view.active {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 72))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                    Text(verbatim: "@\(account.handle ?? account.email ?? "")")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)

            if account.rejected {
                // The server refused this profile's session; signing in again replaces it.
                Section {
                    Label("Your session has expired. Sign in again to keep using this profile.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Sign In Again") {
                        Task { await client.signIn(server: account.server, provider: "tuist") }
                    }
                    .disabled(client.signingIn)
                }
            }

            Section {
                LabeledContent("Email", value: account.email ?? "")
                LabeledContent("Server", value: account.server.hasSuffix("/")
                    ? String(account.server.dropLast()) : account.server)
            }
        }

        Section {
            ThemePicker()
        } footer: {
            Text("Tuist follows the system appearance. Other themes have their own.")
        }

        Section {
            Link(destination: URL(string: "https://tuist.dev/terms")!) { ExternalLinkLabel(title: "Terms of Service") }
            Link(destination: URL(string: "https://tuist.dev/privacy")!) { ExternalLinkLabel(title: "Privacy Policy") }
        }

        Section {
            Link(destination: URL(string: "mailto:contact@tuist.dev")!) { ExternalLinkLabel(title: "Get help") }
        }

        Section {
            LabeledContent(
                "App version",
                value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            )
            PreviewUpdateRow(updater: updater)
        }

        #if os(macOS)
            // System Settings puts account actions in trailing push buttons.
            Section {
                HStack {
                    Button("Delete Account…", role: .destructive) { confirmingDelete = true }
                    Spacer()
                    Button("Sign Out") { Task { await client.perform("sign_out") } }
                }
            }
        #else
            Section {
                Button("Sign out") { Task { await client.perform("sign_out") } }
                    .frame(maxWidth: .infinity)
            }

            Section {
                Button("Delete account", role: .destructive) { confirmingDelete = true }
                    .frame(maxWidth: .infinity)
            }
        #endif
    }
}

private struct ExternalLinkLabel: View {
    let title: LocalizedStringKey

    var body: some View {
        LabeledContent {
            Image(systemName: "arrow.up.forward").foregroundStyle(.tertiary)
        } label: {
            Text(title).foregroundStyle(.primary)
        }
    }
}
