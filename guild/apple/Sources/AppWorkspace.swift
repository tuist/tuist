import SwiftUI

struct AppWorkspace: View {
    @State private var client: AppClient
    @State private var updater: PreviewUpdater
    @State private var addingProfile = false
    /// The selected tab, shown as soon as the person picks it. The core's
    /// `navigation.tab` stays the source of truth; waiting for its answer
    /// would make the tab view render the old tab for a frame.
    @State private var tab = AppNavigation.Tab.threads
    @ObservedObject private var shortcuts = ShortcutInbox.shared
    /// Whether Start conversation shows. `ThreadsView` decides from the core's `navigation.compose`;
    /// the sheet lives here so rebuilding the signed-in views for a new generation keeps it and its draft.
    @State private var startingConversation = false
    @Environment(\.scenePhase) private var scenePhase

    init(client: AppClient) {
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
                        List(selection: $tab) {
                            Label("Threads", systemImage: "bubble.left.and.bubble.right").tag(AppNavigation.Tab.threads)
                            Label("Halls", systemImage: "number").tag(AppNavigation.Tab.halls)
                            Label("DMs", systemImage: "bubble.left.and.text.bubble.right").tag(AppNavigation.Tab.dms)
                            Label("Profile", systemImage: "person.crop.circle").tag(AppNavigation.Tab.profile)
                        }
                        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 280)
                    } detail: {
                        switch tab {
                        case .profile:
                            NavigationStack {
                                ProfileView(client: client, updater: updater, addingProfile: $addingProfile)
                            }
                        case .halls: hallsStack(.halls)
                        case .dms: hallsStack(.dms)
                        case .threads: threadsStack
                        }
                    }
                    .toolbar { ToolbarItem(placement: .primaryAction) { profilesMenu } }
                    .id(client.view.generation)
                #else
                    TabView(selection: $tab) {
                        threadsStack
                            .tabItem { Label("Threads", systemImage: "bubble.left.and.bubble.right") }
                            .tag(AppNavigation.Tab.threads)
                        hallsStack(.halls)
                            .tabItem { Label("Halls", systemImage: "number") }
                            .tag(AppNavigation.Tab.halls)
                        hallsStack(.dms)
                            .tabItem { Label("DMs", systemImage: "bubble.left.and.text.bubble.right") }
                            .tag(AppNavigation.Tab.dms)
                        NavigationStack {
                            ProfileView(client: client, updater: updater, addingProfile: $addingProfile)
                                .toolbar { ToolbarItem(placement: .topBarTrailing) { profilesMenu } }
                        }
                        .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                        .tag(AppNavigation.Tab.profile)
                    }
                    .minimizingTabBarOnScroll()
                    .id(client.view.generation)
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 520)
        #endif
        .onChange(of: tab) { _, tab in
            if tab != client.view.navigation.tab {
                Task { await client.perform("select_tab", ["tab": tab.rawValue]) }
            }
        }
        // Deep links, notification taps and profile switches change the tab in the core.
        .onChange(of: client.view.navigation.tab, initial: true) { _, coreTab in tab = coreTab }
        .focusedSceneValue(\.selectTab, client.view.active == nil ? nil : SelectTabAction { tab = $0 })
        .tint(Noora.primary)
        // Omarchy themes have one appearance; system controls and bars follow it.
        .preferredColorScheme(Themes.shared.selected.appearance)
        .task { await client.start() }
        .onOpenURL { url in Task { await client.openURL(url) } }
        // App Shortcuts route like links; the core holds them until sign-in.
        .onChange(of: shortcuts.path, initial: true) { _, path in
            guard let path else { return }
            shortcuts.path = nil
            Task { await client.perform("navigate", ["url": path]) }
        }
        // Memberships fill the account menu; a failed refresh keeps the saved ones quietly.
        .task(id: client.view.profiles.map(\.id)) {
            if !client.view.profiles.isEmpty { _ = try? await client.call("organizations") }
        }
        .task(id: client.view.active?.id) { await updater.check() }
        // Notifications reach the active profile when it has them on; switching moves them to the new one.
        .task(id: client.view.active?.id) {
            ThreadLiveActivity.shared.profileChanged()
            guard client.view.active != nil else { return }
            await PushNotifications.shared.refresh()
            await PushNotifications.shared.sync()
        }
        // Keeps the person online in their organization while the app is in front.
        .task(id: PresenceKey(generation: client.view.generation, active: scenePhase == .active)) {
            guard scenePhase == .active, client.view.active != nil else {
                _ = try? await client.call("presence_disconnect")
                return
            }
            while !Task.isCancelled {
                _ = try? await client.call("presence")
                try? await Task.sleep(for: .seconds(4))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await updater.check() }
                Task {
                    await PushNotifications.shared.refresh()
                    await PushNotifications.shared.sync()
                }
                // Send what was written offline, such as threads started on a plane.
                Task { _ = try? await client.call("flush_outbox") }
            }
        }
        .sheet(isPresented: $startingConversation, onDismiss: {
            // Cancel and swipe-down leave the core's Start conversation route.
            if client.view.navigation.compose != nil { Task { await client.perform("navigation_back") } }
        }) {
            NavigationStack {
                StartConversationView(
                    client: client, input: client.view.navigation.compose == "dictation" ? .voice : .text
                )
            }
            #if os(iOS)
            .presentationDetents([.medium, .large])
            #endif
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
        .onChange(of: client.view.navigation.revision) { _, _ in addingProfile = false }
        .alert("Something went wrong", isPresented: Binding(
            get: { client.error != nil }, set: { if !$0 { client.error = nil } }
        )) {
            Button("OK") { client.error = nil }
        } message: { Text(verbatim: client.error ?? "") }
    }

    /// The Halls or DMs tab: its list, and the conversation the core says is open in it.
    private func hallsStack(_ tab: AppNavigation.Tab) -> some View {
        let open = tab == .halls ? client.view.navigation.hall_id : client.view.navigation.dm_id
        return NavigationStack(path: Binding(
            get: { open.map { [HallRoute(id: $0)] } ?? [] },
            set: { routes in
                if let route = routes.last, route.id != open {
                    Task { await client.perform("navigate", ["url": "/\(tab.rawValue)/\(route.id)"]) }
                }
                if routes.isEmpty, client.view.navigation.tab == tab, open != nil {
                    Task { await client.perform("navigation_back") }
                }
            }
        )) {
            HallsView(client: client, tab: tab.rawValue)
                .navigationDestination(for: HallRoute.self) { route in
                    HallConversationView(client: client, id: route.id).id(route.id)
                }
        }
    }

    private var threadsStack: some View {
        NavigationStack(path: Binding(
            get: { client.view.navigation.thread_id.map { [ThreadRoute(id: $0)] } ?? [] },
            set: { routes in
                if let route = routes.last, route.id != client.view.navigation.thread_id {
                    Task { await client.perform("navigate", ["url": "/threads/\(route.id)"]) }
                }
                // Native Back/swipe changes the same core state as a URL does.
                if routes.isEmpty, client.view.navigation.tab == .threads, client.view.navigation.thread_id != nil {
                    Task { await client.perform("navigation_back") }
                }
            }
        )) {
            ThreadsView(client: client, starting: $startingConversation)
                .navigationDestination(for: ThreadRoute.self) { route in
                    ConversationView(client: client, id: route.id)
                        .id(route.id)
                }
        }
    }

    /// Switches between the personal accounts and organizations of every saved
    /// profile, adds profiles and signs out: in the window toolbar on the Mac,
    /// and in the Profile tab's navigation bar on iOS.
    private var profilesMenu: some View {
        Menu {
            ForEach(client.view.accounts) { account in
                Toggle(isOn: Binding(
                    get: { account.selected },
                    set: { if $0 { Task { await client.perform(
                        "select_organization", ["id": account.profile_id, "name": account.name]
                    ) } } }
                )) {
                    Text(verbatim: account.name)
                    Text(verbatim: account.personal ? account.server : "@\(account.handle) · \(account.server)")
                }
                .disabled(account.rejected)
            }
            Divider()
            #if os(macOS)
                Button("Add Profile…", systemImage: "person.badge.plus") { addingProfile = true }
                Button("View Profile") { Task { await client.perform("select_tab", ["tab": "profile"]) } }
                Divider()
                Button("Sign Out") { Task { await PushNotifications.shared.signOut() } }
            #else
                Button("Add profile", systemImage: "person.badge.plus") { addingProfile = true }
                Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task { await PushNotifications.shared.signOut() }
                }
            #endif
        } label: {
            Label("Accounts", systemImage: "person.2.circle")
        }
        .help("Switch account")
    }
}

private struct PresenceKey: Equatable {
    let generation: UInt64
    let active: Bool
}

/// The shipping app's Profile page (`app/Sources/TuistProfile/ProfileView.swift`).
/// Switching accounts and adding profiles live in the account menu: the Profile tab's
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

            // Builds without a push entitlement can't receive notifications, so they don't offer them.
            if PushNotifications.environment != nil {
                NotificationsSection(client: client)
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
                    Button("Sign Out") { Task { await PushNotifications.shared.signOut() } }
                }
            }
        #else
            Section {
                Button("Sign out") { Task { await PushNotifications.shared.signOut() } }
                    .frame(maxWidth: .infinity)
            }

            Section {
                Button("Delete account", role: .destructive) { confirmingDelete = true }
                    .frame(maxWidth: .infinity)
            }
        #endif
    }
}

/// The shipping app's opt-in (`app/Sources/TuistNotifications/NotificationsView.swift`):
/// notifications stay off until the person turns them on for the active profile.
private struct NotificationsSection: View {
    let client: AppClient
    @Environment(\.openURL) private var openURL
    private var push: PushNotifications { .shared }

    var body: some View {
        Section {
            Toggle("Notifications on This Device", isOn: Binding(
                get: { push.isEnabled },
                set: { isOn in
                    Task {
                        do { try await push.setEnabled(isOn) }
                        catch { client.error = error.localizedDescription }
                    }
                }
            ))
            .disabled(push.permission == .unknown || push.pendingEnabled != nil)
        } footer: {
            Text("Get notified on this device when a thread you started finishes.")
        }

        if push.permission == .denied {
            Section {
                Button("Turn On in Settings") {
                    #if os(iOS)
                        let settings = UIApplication.openNotificationSettingsURLString
                    #else
                        let settings = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
                    #endif
                    if let url = URL(string: settings) { openURL(url) }
                }
            } footer: {
                Text("Notifications are turned off for Tuist Guild in Settings.")
            }
        }
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
