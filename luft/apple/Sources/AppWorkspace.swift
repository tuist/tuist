import SwiftUI

/// A screen the core's navigation opens: pushed onto a stack, or picked in the iPhone's sidebar.
enum WorkspaceRoute: Hashable {
    case thread(String)
    /// A lounge, or a DM in the DMs stack.
    case lounge(String)
    /// Lounges, DMs, Ops or Profile, picked in the iPhone's sidebar.
    case list(AppNavigation.Tab)
}

struct AppWorkspace: View {
    @State private var client: AppClient
    @State private var updater: PreviewUpdater
    @State private var addingProfile = false
    /// The organization whose settings are open.
    @State private var organizationSettings: OrganizationHandle?
    /// The selected tab, shown as soon as the person picks it. The core's
    /// `navigation.tab` stays the source of truth; waiting for its answer
    /// would make the tab view render the old tab for a frame.
    @State private var tab = AppNavigation.Tab.threads
    @ObservedObject private var shortcuts = ShortcutInbox.shared
    /// Whether Start conversation shows. `ThreadsView` decides from the core's `navigation.compose`;
    /// the sheet lives here so rebuilding the signed-in views for a new generation keeps it and its draft.
    @State private var startingConversation = false
    /// Whether the ⌘K palette is over the window.
    @State private var showingPalette = false
    /// The lists' data, kept while their tabs come and go.
    @State private var inboxes = Inboxes()
    /// The conversation open in each tab, shown at once like `tab`. Reading the core's state
    /// directly would undo a pick, then redo it, until the core caught up.
    @State private var openConversations: [AppNavigation.Tab: String] = [:]
    /// The latest pick sent for each tab; until it lands, the core's older state doesn't move it.
    @State private var conversationRequests: [AppNavigation.Tab: UUID] = [:]
    #if os(iOS)
        /// Whether the iPhone's sidebar is over the open destination.
        @State private var sidebarOpen = false
        /// A pushed record reserves the edge for native Back navigation.
        @State private var recordPresented = false
        /// The finger's horizontal travel while it drags the sidebar; nil otherwise. A gesture state,
        /// so a drag the system cancels can't leave the sidebar stuck partway.
        @GestureState(resetTransaction: Transaction(animation: .snappy(duration: 0.3)))
        private var sidebarDrag: CGFloat?
        /// Destinations opened so far, which stay mounted.
        @State private var visitedTabs: Set<AppNavigation.Tab> = []
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #endif
    @Environment(\.scenePhase) private var scenePhase

    init(client: AppClient) {
        _client = State(initialValue: client)
        _updater = State(initialValue: PreviewUpdater(client: client))
    }

    var body: some View {
        Group {
            if !client.booted {
                // Saved profiles are still loading; showing the login screen
                // now would flash it before a signed-in workspace.
                Color.clear
            } else if client.view.active == nil {
                LogInView(client: client)
            } else {
                #if os(macOS)
                    // On the Mac, a source-list sidebar takes the place of the tab bar. Conversations
                    // follow Mail and Messages: sidebar, list, then the selected conversation, so the
                    // list stays in view with its selection while a conversation is open.
                    Group {
                        if tab == .profile || tab == .ops {
                            NavigationSplitView {
                                sidebar
                            } detail: {
                                NavigationStack {
                                    if tab == .ops {
                                        OpsView(client: client)
                                    } else {
                                        ProfileView(client: client, updater: updater, addingProfile: $addingProfile)
                                    }
                                }
                                // Each its own stack: Collections pushed in Ops doesn't follow to Profile.
                                .id(tab)
                            }
                        } else {
                            NavigationSplitView {
                                sidebar
                            } content: {
                                conversationList
                                    .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 440)
                            } detail: {
                                openConversation
                            }
                        }
                    }
                    .toolbar { ToolbarItem(placement: .primaryAction) { profilesMenu } }
                    .id(client.view.generation)
                #else
                    sidebarStack.id(client.view.generation)
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
        // Deep links, notification taps and Back change the open conversations in the core too.
        .onChange(of: client.view.navigation.thread_id, initial: true) { _, _ in followCore(.threads) }
        .onChange(of: client.view.navigation.lounge_id, initial: true) { _, _ in followCore(.lounges) }
        .onChange(of: client.view.navigation.dm_id, initial: true) { _, _ in followCore(.dms) }
        .focusedSceneValue(\.selectTab, client.view.active == nil ? nil : SelectTabAction { tab = $0 })
        .focusedSceneValue(\.commandPalette, client.view.active == nil ? nil : CommandPaletteAction {
            showingPalette.toggle()
        })
        .overlay(alignment: .top) {
            if showingPalette, client.view.active != nil {
                ZStack(alignment: .top) {
                    // Clicking outside closes it, like Spotlight.
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                        .onTapGesture { showingPalette = false }
                        .accessibilityHidden(true)
                    CommandPalette(client: client) { showingPalette = false }
                        .padding(.top, 72)
                        .padding(.horizontal, 16)
                }
            }
        }
        // Another account has other threads and lounges.
        .onChange(of: client.view.generation) { _, _ in showingPalette = false }
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
        .sheet(item: $organizationSettings) { organization in
            OrganizationSettingsView(client: client, handle: organization.id)
        }
        .onChange(of: client.view.generation) { _, _ in
            addingProfile = false
            organizationSettings = nil
        }
        .onChange(of: client.view.navigation.revision) { _, _ in addingProfile = false }
        .alert("Something went wrong", isPresented: Binding(
            get: { client.error != nil }, set: { if !$0 { client.error = nil } }
        )) {
            Button("OK") { client.error = nil }
        } message: { Text(verbatim: client.error ?? "") }
        // A newer preview found at launch or on returning: suggest it once; Profile keeps the Update row.
        .alert("New version available", isPresented: $updater.suggesting) {
            Button("Update") { Task { await updater.install() } }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Update Luft to stay on the latest preview.")
        }
    }

    /// The Lounges or DMs list, and the conversation the core says is open in it.
    private func loungesStack(_ tab: AppNavigation.Tab) -> some View {
        NavigationStack(path: Binding(
            get: { openConversations[tab].map { [WorkspaceRoute.lounge($0)] } ?? [] },
            set: { routes in
                if case let .lounge(id) = routes.last { show(id, in: tab) } else { show(nil, in: tab) }
            }
        )) {
            LoungesView(client: client, tab: tab.rawValue, inbox: inboxes.lounges(client.view.generation))
            #if os(iOS)
                .toolbar { sidebarButton }
            #endif
                .navigationDestination(for: WorkspaceRoute.self) { destination($0) }
        }
    }

    #if os(macOS)
        private var sidebar: some View {
            List(selection: $tab) {
                Label("Threads", systemImage: "bubble.left.and.bubble.right").tag(AppNavigation.Tab.threads)
                Label("Lounges", systemImage: "number").tag(AppNavigation.Tab.lounges)
                Label("DMs", systemImage: "bubble.left.and.text.bubble.right").tag(AppNavigation.Tab.dms)
                Label("Ops", systemImage: "wrench.and.screwdriver").tag(AppNavigation.Tab.ops)
                Label("Profile", systemImage: "person.crop.circle").tag(AppNavigation.Tab.profile)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 280)
        }

        /// The conversation open in this tab.
        private var openID: String? { openConversations[tab] }

        /// The list's selection is the open conversation: picking a row navigates like a
        /// link does, and links and notifications select their row.
        private var selection: Binding<String?> {
            Binding(get: { openID }, set: { show($0, in: tab) })
        }

        @ViewBuilder private var conversationList: some View {
            switch tab {
            case .threads:
                ThreadsView(
                    client: client, starting: $startingConversation,
                    inbox: inboxes.threads(client.view.generation), selection: selection
                )
            case .lounges, .dms:
                LoungesView(
                    client: client, tab: tab.rawValue,
                    inbox: inboxes.lounges(client.view.generation), selection: selection
                )
            case .profile, .ops: EmptyView()
            }
        }

        @ViewBuilder private var openConversation: some View {
            if let id = openID {
                NavigationStack { destination(tab == .threads ? .thread(id) : .lounge(id)) }
            } else {
                ContentUnavailableView(
                    tab == .threads ? "No Thread Selected" : "No Conversation Selected",
                    systemImage: tab == .threads ? "bubble.left.and.bubble.right" : "bubble.left.and.text.bubble.right"
                )
            }
        }
    #else
        /// The iPhone shows one destination, the one the core's tab and stacks say is open, so links
        /// and notifications land in the same place. The sidebar slides over it, as in Claude.
        private var sidebarStack: some View {
            GeometryReader { geometry in
                let width = min(geometry.size.width * 0.85, 360)
                let base: CGFloat = sidebarOpen ? 0 : -width
                // How far out the sidebar is: -width when closed, 0 when open, between while dragged.
                let offset = min(0, max(-width, base + (sidebarDrag ?? 0)))
                let shown = 1 + offset / width
                let visible = sidebarOpen || sidebarDrag != nil
                ZStack(alignment: .leading) {
                    // Destinations stay mounted once visited, like tabs, so going back to one keeps its
                    // list and scroll instead of loading it again.
                    ZStack {
                        ForEach([AppNavigation.Tab.threads, .lounges, .dms, .ops, .profile], id: \.self) { tab in
                            if visitedTabs.contains(tab) {
                                let current = tab == client.view.navigation.tab
                                destinationStack(tab)
                                    .opacity(current ? 1 : 0)
                                    .allowsHitTesting(current)
                                    .accessibilityHidden(!current || visible)
                                    .onPreferenceChange(RecordPresentedKey.self) { presented in
                                        if current { recordPresented = presented }
                                    }
                            }
                        }
                    }
                    // Swiping in from the edge pulls the sidebar out under the finger; once a lounge
                    // is open, the edge goes Back instead. It stays while the finger drags from it.
                    .overlay(alignment: .leading) {
                        if !sidebarOpen, canOpenSidebarFromEdge {
                            Color.clear.frame(width: 20).contentShape(Rectangle())
                                .gesture(sidebarGesture(width: width, minimumDistance: 5))
                                // Below the navigation bar, so it never takes taps meant for the sidebar button.
                                .padding(.top, 56)
                        }
                    }

                    Color.black.opacity(0.3 * shown)
                        .ignoresSafeArea()
                        .allowsHitTesting(visible)
                        .onTapGesture { setSidebar(open: false) }
                        .gesture(sidebarGesture(width: width, minimumDistance: 10))
                        .accessibilityHidden(true)

                    // Kept mounted, so it opens with its threads already there; hidden from VoiceOver
                    // while offscreen. Start conversation is the chat screen behind it, never a sheet.
                    NavigationStack {
                        ThreadsView(
                            client: client, starting: .constant(false), inbox: inboxes.threads(client.view.generation),
                            open: { open($0) },
                            search: {
                                setSidebar(open: false)
                                showingPalette = true
                            }
                        )
                    }
                    .frame(width: width)
                    .background(Noora.backgroundPrimary.ignoresSafeArea())
                    .shadow(color: .black.opacity(0.2 * shown), radius: 16)
                    .offset(x: offset)
                    .simultaneousGesture(sidebarGesture(width: width, minimumDistance: 20))
                    .allowsHitTesting(visible)
                    .accessibilityHidden(!visible)
                    // VoiceOver stays in the sidebar instead of reaching the screen it covers.
                    .accessibilityAddTraits(visible ? .isModal : [])
                    .accessibilityAction(.escape) { setSidebar(open: false) }
                }
            }
            .onChange(of: client.view.navigation.tab, initial: true) { _, tab in visitedTabs.insert(tab) }
            // Starting a conversation, from the sidebar or a shortcut, shows the chat screen.
            .onChange(of: client.view.navigation.compose) { _, compose in
                if compose != nil { setSidebar(open: false) }
            }
        }

        /// A destination's own navigation stack, with the sidebar button at its root.
        @ViewBuilder private func destinationStack(_ tab: AppNavigation.Tab) -> some View {
            switch tab {
            case .threads:
                NavigationStack { threadsRoot.toolbar { sidebarButton } }
            case .lounges, .dms:
                loungesStack(tab)
            case .profile, .ops:
                NavigationStack { destination(.list(tab)).toolbar { sidebarButton } }
            }
        }

        /// The open thread, or a new chat when none is.
        @ViewBuilder private var threadsRoot: some View {
            let navigation = client.view.navigation
            if let id = navigation.thread_id {
                ConversationView(client: client, id: id).id(id)
            } else {
                // A new chat; the core's Start conversation route (`compose`) raises its keyboard or dictation.
                StartConversationView(client: client, input: navigation.compose.map { $0 == "dictation" ? .voice : .text })
            }
        }

        private var sidebarButton: some ToolbarContent {
            ToolbarItem(placement: .topBarLeading) {
                Button("Open sidebar", systemImage: "line.3.horizontal") { setSidebar(open: true) }
            }
        }

        /// Nothing is pushed in the open destination, so its edge is free for the sidebar.
        private var canOpenSidebarFromEdge: Bool {
            guard !recordPresented else { return false }
            let navigation = client.view.navigation
            return switch navigation.tab {
            case .lounges: navigation.lounge_id == nil
            case .dms: navigation.dm_id == nil
            case .threads, .profile, .ops: true
            }
        }

        /// Moves the sidebar with the finger, then settles it open or closed by where the swipe was heading.
        private func sidebarGesture(width: CGFloat, minimumDistance: CGFloat) -> some Gesture {
            DragGesture(minimumDistance: minimumDistance)
                .updating($sidebarDrag) { value, drag, _ in
                    // A mostly vertical drag is the list scrolling, not the sidebar.
                    if drag == nil, abs(value.translation.height) > abs(value.translation.width) { return }
                    drag = value.translation.width
                }
                .onEnded { value in
                    guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                    let base: CGFloat = sidebarOpen ? 0 : -width
                    setSidebar(open: base + value.predictedEndTranslation.width > -width / 2)
                }
        }

        private func setSidebar(open: Bool) {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { sidebarOpen = open }
        }

        /// Opens what the person picked in the sidebar and closes it.
        private func open(_ route: WorkspaceRoute) {
            setSidebar(open: false)
            let url = switch route {
            case let .thread(id): "/threads/\(id)"
            case let .lounge(id): "/\(client.view.navigation.tab.rawValue)/\(id)"
            // Lounges and DMs open at their list, not a conversation left open there.
            case let .list(tab): "/\(tab.rawValue)"
            }
            Task { await client.perform("navigate", ["url": url]) }
        }
    #endif

    @ViewBuilder private func destination(_ route: WorkspaceRoute) -> some View {
        switch route {
        case let .thread(id): ConversationView(client: client, id: id).id(id)
        case let .lounge(id):
            LoungeConversationView(client: client, id: id, listedTitle: listedLoungeTitle(id)).id(id)
        case .list(.profile):
            ProfileView(client: client, updater: updater, addingProfile: $addingProfile)
            #if os(iOS)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { profilesMenu } }
            #endif
        case .list(.ops): OpsView(client: client)
        case let .list(tab): LoungesView(client: client, tab: tab.rawValue, inbox: inboxes.lounges(client.view.generation))
        }
    }

    /// Opens a conversation in a tab, or closes it with nil: here at once, then in the core.
    private func show(_ id: String?, in tab: AppNavigation.Tab) {
        guard id != openConversations[tab] else { return }
        openConversations[tab] = id
        let request = UUID()
        conversationRequests[tab] = request
        Task {
            if let id {
                await client.perform("navigate", ["url": "/\(tab.rawValue)/\(id)"])
            } else if client.view.navigation.tab == tab {
                await client.perform("navigation_back")
            }
            // Landed or failed: from now on the tab shows what the core says.
            if conversationRequests[tab] == request {
                conversationRequests[tab] = nil
                followCore(tab)
            }
        }
    }

    /// Shows the core's open conversation in a tab, unless a newer pick made here is still on its way.
    private func followCore(_ tab: AppNavigation.Tab) {
        guard conversationRequests[tab] == nil else { return }
        let navigation = client.view.navigation
        openConversations[tab] = switch tab {
        case .threads: navigation.thread_id
        case .lounges: navigation.lounge_id
        case .dms: navigation.dm_id
        case .profile, .ops: nil
        }
    }

    private func listedLoungeTitle(_ id: String) -> String? {
        let page = inboxes.lounges(client.view.generation).page
        return (page?.lounges ?? []).first { $0.id == id }?.title ?? (page?.directs ?? []).first { $0.id == id }?.title
    }

    /// Switches between the personal accounts and organizations of every saved
    /// profile, adds profiles and signs out: in the window toolbar on the Mac,
    /// and in Profile's navigation bar on iOS.
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
            if let organization = selectedOrganization {
                #if os(macOS)
                    Button("Organization Settings…", systemImage: "building.2") { organizationSettings = OrganizationHandle(id: organization.handle) }
                #else
                    Button("Organization settings", systemImage: "building.2") { organizationSettings = OrganizationHandle(id: organization.handle) }
                #endif
                Divider()
            }
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

    /// The organization the active profile works in, when it isn't the personal account.
    private var selectedOrganization: AppAccount? {
        guard let active = client.view.active, !active.rejected else { return nil }
        return client.view.accounts.first { $0.profile_id == active.id && $0.selected && !$0.personal }
    }
}

/// A sheet a settings section opens. The settings form presents it rather than the section:
/// a sheet attached inside the form's lazy rows closes when the rows reload, as they do while
/// the sections load on the first visit.
struct SettingsSheet: Identifiable {
    let id = UUID()
    let content: AnyView

    init(@ViewBuilder _ content: () -> some View) {
        self.content = AnyView(content())
    }
}

/// The selected organization's settings, apart from the person's own in Profile.
private struct OrganizationSettingsView: View {
    let client: AppClient
    let handle: String
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: SettingsSheet?

    var body: some View {
        NavigationStack {
            Form {
                MCPServersSection(client: client, accountHandle: handle, sheet: $sheet)
                    .listRowBackground(Noora.backgroundTertiary)
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .scrollContentBackground(.hidden)
            .background(Noora.backgroundPrimary)
            .sheet(item: $sheet) { $0.content }
            .navigationTitle("Organization Settings")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 360)
        #endif
    }
}

/// The lists' data for one signed-in generation. Another account or organization starts
/// empty ones as it renders, so a list never shows the previous account's rows.
@MainActor private final class Inboxes {
    private var generation: UInt64?
    private var threadInbox = ThreadInbox()
    private var loungeInbox = LoungeInbox()

    func threads(_ generation: UInt64) -> ThreadInbox {
        reset(generation)
        return threadInbox
    }

    func lounges(_ generation: UInt64) -> LoungeInbox {
        reset(generation)
        return loungeInbox
    }

    private func reset(_ generation: UInt64) {
        guard generation != self.generation else { return }
        self.generation = generation
        threadInbox = ThreadInbox()
        loungeInbox = LoungeInbox()
    }
}

private struct OrganizationHandle: Identifiable {
    let id: String
}

private struct PresenceKey: Equatable {
    let generation: UInt64
    let active: Bool
}

/// The shipping app's Profile page (`app/Sources/TuistProfile/ProfileView.swift`).
/// Switching accounts and adding profiles live in the account menu: Profile's
/// navigation bar on iOS and the window toolbar on macOS.
private struct ProfileView: View {
    let client: AppClient
    let updater: PreviewUpdater
    @Binding var addingProfile: Bool
    @State private var confirmingDelete = false
    @State private var sheet: SettingsSheet?

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
        .sheet(item: $sheet) { $0.content }
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
                    Label(
                        "Your session has expired. Sign in again to keep using this profile.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    Button("Sign In Again") {
                        Task { await client.signIn(server: account.server, provider: "tuist") }
                    }
                    .disabled(client.signingIn)
                }
            }

            Section {
                LabeledContent("Email", value: account.email ?? "")
                LabeledContent(
                    "Server",
                    value: account.server.hasSuffix("/")
                        ? String(account.server.dropLast()) : account.server
                )
            }

            // The organization's servers are in Organization Settings, in the account menu.
            if !account.rejected {
                AISubscriptionsSection(client: client, sheet: $sheet)
                MCPServersSection(client: client, accountHandle: nil, sheet: $sheet)
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

/// Collections and Releases: what the person operates, apart from their Profile.
private struct OpsView: View {
    let client: AppClient

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    CollectionsView(client: client)
                        .preference(key: RecordPresentedKey.self, value: true)
                } label: {
                    Label("Collections", systemImage: "rectangle.stack")
                }
                NavigationLink {
                    ReleasesView(client: client)
                } label: {
                    Label("Releases", systemImage: "shippingbox")
                }
            }
            .listRowBackground(Noora.backgroundTertiary)
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Noora.backgroundPrimary)
        .navigationTitle("Ops")
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
                Text("Notifications are turned off for Luft in Settings.")
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
