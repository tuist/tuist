import SwiftUI

struct AppThread: Decodable, Identifiable {
    let id: String
    let title: String?
    let goal: String?
    let repository: String?
    /// `queued`, `running`, `completed`, `failed`, `outcome_unknown` or nil, decided by the Rust core.
    let state: String?
    /// `in_progress`, `recent`, `snoozed` or `archived`, decided by the Rust core.
    let section: String
    /// Set while the person snoozed it, decided by the Rust core.
    var snooze: AppSnooze?

    var working: Bool { state == "queued" || state == "running" }
}

private struct Freshness: Decodable {
    /// `live`, `cached`, `queued` or `never_loaded`, decided by the Rust core.
    let state: String
}

private struct ThreadPage: Decodable {
    let freshness: Freshness?
    let available: Bool
    /// Why threads are unavailable: `disabled`, or `sign_in_required` (the session predates Luft's first-party client).
    let reason: String?
    let threads: [AppThread]
    let next_cursor: String?
}

extension AppClient {
    /// Opens Start conversation through the core's `/threads/new` route.
    func startConversation() {
        Task {
            // A request the sheet never showed leaves `compose` set; navigating to it again
            // would not change it, so leave it first.
            if view.navigation.compose != nil { await perform("navigation_back") }
            await perform("navigate", ["url": "/threads/new"])
        }
    }
}

#if os(iOS)
    private extension View {
        /// A sidebar row on the background, like chats in Claude, marked when it is open.
        func sidebarRow(selected: Bool) -> some View {
            // Dense like Claude's, but still the 44-point tap target the HIG asks for.
            frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .listRowBackground(selected ? Noora.backgroundTertiary : Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }

    /// Only the icon where the title wouldn't fit; VoiceOver reads the title either way.
    private struct SidebarLabelStyle: LabelStyle {
        let iconOnly: Bool

        @ViewBuilder func makeBody(configuration: Configuration) -> some View {
            if iconOnly {
                configuration.icon
            } else {
                Label(configuration)
            }
        }
    }
#endif

/// The threads inbox: Active and Archived, with running threads first and
/// snoozed ones last, out of the way until they matter again.
struct ThreadsView: View {
    let client: AppClient
    /// Start conversation, presented by `AppWorkspace`.
    @Binding var starting: Bool
    /// The Mac's open thread: the list is the middle column of a split view, as in Mail.
    var selection: Binding<String?> = .constant(nil)
    /// Opens a destination from the iPhone's sidebar, which then closes.
    var open: (WorkspaceRoute) -> Void = { _ in }
    @State private var threads: [AppThread] = []
    @State private var nextCursor: String?
    @State private var loaded = false
    @State private var available = true
    @State private var signInRequired = false
    @State private var loading: Task<Void, Never>?
    @State private var showingArchived = false
    @State private var error: String?
    @State private var snoozeChoices = SnoozeChoices()
    /// The thread whose snooze choices show, after a swipe.
    @State private var snoozing: AppThread?
    /// The thread a custom time is being picked for.
    @State private var customSnooze: AppThread?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var iconWidth = 20.0

    var body: some View {
        list
        #if os(macOS)
        .listStyle(.inset)
        #else
        .listStyle(.plain)
        .safeAreaInset(edge: .bottom) { sidebarBar }
        #endif
        .scrollContentBackground(.hidden)
        .background(Noora.backgroundPrimary)
        // Overlays center in the content area; list rows would stack at the top.
        .overlay {
            if error == nil {
                if !loaded {
                    ProgressView()
                } else if signInRequired {
                    ContentUnavailableView {
                        Label("Sign in again to use threads", systemImage: "person.badge.key")
                    } description: {
                        Text("Your session is from an earlier version of Luft.")
                    } actions: {
                        if let server = client.view.active?.server {
                            Button("Sign In Again") { Task { await client.signIn(server: server, provider: "tuist") } }
                                .buttonStyle(.borderedProminent)
                                .disabled(client.signingIn)
                        }
                    }
                } else if !available {
                    ContentUnavailableView(
                        "Threads aren't available yet",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Threads aren't enabled for this account or server.")
                    )
                } else if visible.isEmpty, nextCursor == nil {
                    if showingArchived {
                        ContentUnavailableView(
                            "All clear, nothing archived",
                            systemImage: "archivebox",
                            description: Text("Archived threads will live here. You can come back to them anytime.")
                        )
                    } else {
                        ContentUnavailableView {
                            Label("Big things start here", systemImage: "bubble.left.and.bubble.right")
                        } description: {
                            Text("Ask a question, explore an idea, or solve a problem with Tuist.")
                        } actions: {
                            Button("Start conversation") { startConversation() }.prominentGlassButtonStyle()
                        }
                    }
                }
            }
        }
        #if os(iOS)
            // A small name in the corner instead of a large title, so the threads start near the top.
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                Text(verbatim: "Luft")
                    .font(.headline)
                    .foregroundStyle(Noora.labelPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Noora.backgroundPrimary)
            }
            // Section labels stay short; tappable rows keep their own 44-point minimum.
            .environment(\.defaultMinListRowHeight, 1)
        #else
            .navigationTitle("Threads")
            .toolbar {
                if available {
                    ToolbarItem(placement: .principal) { archivePicker }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Start conversation", systemImage: "square.and.pencil") { startConversation() }
                            .keyboardShortcut("n", modifiers: .command)
                            .help("Start conversation")
                    }
                }
            }
            .toolbar {
                // The Mac has no pull-to-refresh.
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await reload() } }
                        .keyboardShortcut("r", modifiers: .command)
                        .help("Refresh threads")
                }
            }
        #endif
        .refreshable { await reload() }
        .task { await snoozeChoices.follow(client) }
        // Dialog buttons take the presenting view's tint; the choices read as plain text.
        .background {
            Color.clear.confirmationDialog(
                "Snooze", isPresented: Binding(get: { snoozing != nil }, set: { if !$0 { snoozing = nil } }),
                titleVisibility: .visible, presenting: snoozing
            ) { thread in
                SnoozeButtons(
                    choices: snoozeChoices,
                    working: thread.working,
                    snoozed: thread.snooze != nil,
                    inline: true,
                    snooze: { snooze(thread, until: $0) },
                    custom: { customSnooze = thread }
                )
            } message: { thread in
                Text(verbatim: thread.title ?? thread.goal ?? "")
            }
            .tint(Noora.labelPrimary)
        }
        .sheet(item: $customSnooze) { thread in
            CustomSnoozeView { snooze(thread, until: $0) }
        }
        .task(id: client.view.active_profile_id) {
            // Render what's on the device first, then bring it up to date.
            await fetch(operation: "cached_threads", cursor: nil)
            await reload()
        }
        // The core opens Start conversation (`navigation.compose`) and closes it on any other navigation.
        .onChange(of: client.view.navigation.compose, initial: true) { previous, compose in
            showStartConversation()
            // Closing it, after starting a thread or not, can change the inbox.
            if previous != nil, compose == nil { Task { await reload() } }
        }
        .onChange(of: available) { _, _ in showStartConversation() }
        // Signing in again keeps the profile's ID, so reload once the browser closes.
        .onChange(of: client.signingIn) { _, signingIn in
            if !signingIn, signInRequired { Task { await reload() } }
        }
    }

    private var list: some View {
        #if os(macOS)
            List(selection: selection) { rows }
        #else
            List { rows }
        #endif
    }

    @ViewBuilder private var rows: some View {
        #if os(iOS)
            // The iPhone's sidebar: the other destinations above the threads, like Claude's.
            Section {
                sidebarLink("Halls", systemImage: "number", to: .list(.halls))
                sidebarLink("DMs", systemImage: "bubble.left.and.text.bubble.right", to: .list(.dms))
            }
            if available {
                archivePicker
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
        #endif
        if let error {
            Section {
                Text(verbatim: error).foregroundStyle(.secondary)
                Button("Try again") { Task { await reload() } }
            }
        }
        if !showingArchived {
            section("In progress", visible.filter { $0.section == "in_progress" })
            section("Recent", visible.filter { $0.section == "recent" })
            // Out of the way, still a scroll away.
            section("Snoozed", visible.filter { $0.section == "snoozed" })
        } else {
            section("Archived", visible)
        }
        if nextCursor != nil {
            Button("Load more threads") { Task { await loadMore() } }.disabled(loading != nil)
        }
    }

    private func startConversation() {
        client.startConversation()
    }

    /// Shows Start conversation while the core asks for it. When threads are unavailable,
    /// a request (say, from a shortcut) can't be shown, so it leaves the route instead of keeping it.
    private func showStartConversation() {
        guard client.view.navigation.compose != nil else {
            starting = false
            return
        }
        if available {
            starting = true
        } else {
            starting = false
            Task { await client.perform("navigation_back") }
        }
    }

    #if os(iOS)
        private func sidebarLink(_ title: LocalizedStringKey, systemImage: String, to route: WorkspaceRoute) -> some View {
            Button { open(route) } label: {
                Label(title, systemImage: systemImage).foregroundStyle(Noora.labelPrimary)
            }
            .sidebarRow(selected: route == .list(client.view.navigation.tab))
        }

        /// Profile and New conversation float under the sidebar, as in Claude.
        private var sidebarBar: some View {
            HStack {
                Button { open(.list(.profile)) } label: {
                    Text(verbatim: String((client.view.active?.handle ?? client.view.active?.email ?? "?").prefix(1)).uppercased())
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Noora.labelPrimary)
                        .frame(width: 52, height: 52)
                        .interactiveGlass(in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profile")
                Spacer()
                if available {
                    Button { startConversation() } label: {
                        Label("New conversation", systemImage: "plus")
                            .labelStyle(SidebarLabelStyle(iconOnly: dynamicTypeSize.isAccessibilitySize))
                            .font(.body.weight(.medium))
                            .padding(.horizontal, 8)
                            .frame(height: 40)
                    }
                    .prominentGlassButtonStyle()
                    .buttonBorderShape(.capsule)
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            // Threads scroll under the bar, so it hides them like Claude's does.
            .background(Noora.backgroundPrimary)
            .overlay(alignment: .top) { Divider() }
        }
    #endif

    private var archivePicker: some View {
        Picker("Threads", selection: $showingArchived) {
            Text("Active").tag(false)
            Text("Archived").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var visible: [AppThread] {
        threads.filter { ($0.section == "archived") == showingArchived }
    }

    @ViewBuilder private func section(_ title: LocalizedStringKey, _ values: [AppThread]) -> some View {
        if !values.isEmpty {
            #if os(iOS)
                // A small label row, as in Claude's sidebar: plain list sections add tall headers and gaps.
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Noora.labelSecondary)
                    .accessibilityAddTraits(.isHeader)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                ForEach(values) { thread in
                    snoozable(thread) {
                        Button { open(.thread(thread.id)) } label: { row(thread) }
                            .sidebarRow(selected: client.view.navigation.tab == .threads
                                && client.view.navigation.thread_id == thread.id)
                    }
                }
            #else
                Section(title) {
                    ForEach(values) { thread in
                        snoozable(thread) {
                            // A list of conversations, as in Mail, not a data table: no row fills
                            // or rules, only the system's selection.
                            row(thread)
                                .tag(thread.id)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
                .listSectionSeparator(.hidden)
            #endif
        }
    }

    /// A thread's row, snoozed or woken with a swipe or from its context menu.
    private func snoozable(_ thread: AppThread, @ViewBuilder _ row: () -> some View) -> some View {
        row()
            .swipeActions(edge: .leading) { snoozeAction(thread) }
            .contextMenu {
                if thread.section != "archived" {
                    Menu("Snooze", systemImage: "moon.zzz") {
                        SnoozeButtons(
                            choices: snoozeChoices,
                            working: thread.working,
                            snoozed: thread.snooze != nil,
                            snooze: { snooze(thread, until: $0) },
                            custom: { customSnooze = thread }
                        )
                    }
                }
            }
    }

    @ViewBuilder private func snoozeAction(_ thread: AppThread) -> some View {
        if thread.snooze != nil {
            Button("Wake", systemImage: "sun.max") { snooze(thread, until: nil) }.tint(.orange)
        } else if thread.section != "archived" {
            Button("Snooze", systemImage: "moon.zzz") { snoozing = thread }.tint(.indigo)
        }
    }

    /// Snoozes or wakes a thread, then shows the inbox as the core sorts it now.
    private func snooze(_ thread: AppThread, until: String?) {
        Task {
            do {
                _ = try await client.snooze(thread.id, until: until)
                await reload()
            } catch {
                client.error = error.localizedDescription
            }
        }
    }

    private func row(_ thread: AppThread) -> some View {
        let detail = [thread.repository, thread.snooze?.label ?? statusLabel(thread.state)]
            .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: thread.section == "archived" ? "archivebox"
                : thread.section == "snoozed" ? "moon.zzz"
                : thread.section == "in_progress" ? "circle.dotted" : "bubble.left")
                .foregroundStyle(thread.section == "in_progress" ? Noora.primary : Noora.labelSecondary)
                .frame(width: iconWidth)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: thread.title ?? thread.goal ?? "").font(.body.weight(.medium))
                    // One line per chat in the iPhone's sidebar, as in Claude's.
                    // Titles wrap at accessibility sizes instead of hiding behind an ellipsis.
                    #if os(iOS)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    #else
                    .lineLimit(2)
                    #endif
                    .foregroundStyle(Noora.labelPrimary)
                if !detail.isEmpty {
                    Text(verbatim: detail).font(.caption).foregroundStyle(Noora.labelSecondary)
                }
            }
        }
        // The Mac's rows breathe like Mail's; the iPhone's sidebar stays dense like Claude's.
        #if os(macOS)
        .padding(.vertical, 6)
        #else
        .padding(.vertical, 2)
        #endif
    }

    private func statusLabel(_ state: String?) -> String? {
        switch state {
        case "queued": String(localized: "Queued")
        case "running": String(localized: "Running")
        case "completed": String(localized: "Ready to review")
        case "failed": String(localized: "Needs attention")
        case "outcome_unknown": String(localized: "Outcome unknown")
        default: nil
        }
    }

    /// Replaces the list. A refresh supersedes a load in flight rather than being dropped.
    private func reload() async {
        loading?.cancel()
        await run(cursor: nil)
    }

    private func loadMore() async {
        guard loading == nil, let cursor = nextCursor else { return }
        await run(cursor: cursor)
    }

    private func run(cursor: String?) async {
        let task = Task { await fetch(operation: "threads", cursor: cursor) }
        loading = task
        await task.value
        if loading == task { loading = nil }
    }

    private func fetch(operation: String, cursor: String?) async {
        let profile = client.view.active_profile_id
        do {
            let data = try await client.call(operation, cursor.map { ["cursor": $0] } ?? [:])
            let page = try JSONDecoder().decode(ThreadPage.self, from: JSONSerialization.data(withJSONObject: data))
            // A newer load, or another profile, owns the list now.
            guard !Task.isCancelled, profile == client.view.active_profile_id else { return }
            // The core returns the whole stored inbox, with queued threads, for every page.
            threads = page.threads
            nextCursor = page.next_cursor
            available = page.available
            signInRequired = page.reason == "sign_in_required"
            error = nil
            // An inbox never loaded on this device isn't empty, only unknown yet.
            if page.freshness?.state != "never_loaded" { loaded = true }
            // Only what the server just said: a cached inbox can show threads that finished since.
            if operation == "threads", page.freshness?.state == "live",
               page.threads.contains(where: { $0.section == "in_progress" })
            {
                ThreadLiveActivity.shared.threadsWorking()
            }
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
            loaded = true
        }
    }
}
