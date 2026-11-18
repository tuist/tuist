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

/// The threads inbox: Active and Archived, with running threads first and
/// snoozed ones last, out of the way until they matter again.
struct ThreadsView: View {
    let client: AppClient
    /// Start conversation, presented by `AppWorkspace`.
    @Binding var starting: Bool
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

    var body: some View {
        List {
            #if os(iOS)
                // In the title's place it would hide "Threads", so it heads the list instead.
                if available {
                    archivePicker
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
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
        #if os(macOS)
        .listStyle(.inset)
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
        .navigationTitle("Threads")
        .toolbar {
            if available {
                #if os(macOS)
                    ToolbarItem(placement: .principal) { archivePicker }
                #endif
                ToolbarItem(placement: .primaryAction) {
                    Button("Start conversation", systemImage: "square.and.pencil") { startConversation() }
                        .keyboardShortcut("n", modifiers: .command)
                        .help("Start conversation")
                }
            }
        }
        #if os(macOS)
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

    private func startConversation() {
        Task {
            // A request the sheet never showed leaves `compose` set; navigating to it again
            // would not change it, so leave it first.
            if client.view.navigation.compose != nil { await client.perform("navigation_back") }
            await client.perform("navigate", ["url": "/threads/new"])
        }
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
            Section(title) {
                ForEach(values) { thread in
                    NavigationLink(value: ThreadRoute(id: thread.id)) { row(thread) }
                        .listRowBackground(Noora.backgroundTertiary)
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: thread.section == "archived" ? "archivebox"
                : thread.section == "snoozed" ? "moon.zzz"
                : thread.section == "in_progress" ? "circle.dotted" : "bubble.left")
                .foregroundStyle(thread.section == "in_progress" ? Noora.primary : Noora.labelSecondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: thread.title ?? thread.goal ?? "").font(.body.weight(.medium)).lineLimit(2)
                    .foregroundStyle(Noora.labelPrimary)
                Text(verbatim: [thread.repository, thread.snooze?.label ?? statusLabel(thread.state)]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Noora.labelSecondary)
            }
        }
        .padding(.vertical, 2)
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
