import SwiftUI

struct AppThread: Decodable, Identifiable {
    let id: String
    let title: String?
    let goal: String?
    let repository: String?
    /// `queued`, `running`, `completed`, `failed`, `outcome_unknown` or nil, decided by the Rust core.
    let state: String?
    /// `in_progress`, `recent` or `archived`, decided by the Rust core.
    let section: String
}

private struct ThreadPage: Decodable {
    let available: Bool
    /// Why threads are unavailable: `disabled` or `forbidden` (not an admin of the organization).
    let reason: String?
    let threads: [AppThread]
    let next_cursor: String?
}

/// The threads inbox: Active and Archived, with running threads first.
struct ThreadsView: View {
    let client: AppClient
    @State private var threads: [AppThread] = []
    @State private var nextCursor: String?
    @State private var loaded = false
    @State private var available = true
    @State private var forbidden = false
    @State private var loading: Task<Void, Never>?
    @State private var showingArchived = false
    @State private var error: String?
    @State private var starting = false

    var body: some View {
        List {
            if let error {
                Section {
                    Text(verbatim: error).foregroundStyle(.secondary)
                    Button("Try again") { Task { await reload() } }
                }
            }
            if !showingArchived {
                section("In progress", visible.filter { $0.section == "in_progress" })
                section("Recent", visible.filter { $0.section == "recent" })
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
                } else if forbidden {
                    ContentUnavailableView(
                        "Only admins can use threads here",
                        systemImage: "lock",
                        description: Text("Ask an admin of \(account) for access, or switch to another account.")
                    )
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
                            Button("Start conversation") { starting = true }.prominentGlassButtonStyle()
                        }
                    }
                }
            }
        }
        .navigationTitle("Threads")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if available {
                ToolbarItem(placement: .principal) { archivePicker }
                ToolbarItem(placement: .primaryAction) {
                    Button("Start conversation", systemImage: "square.and.pencil") { starting = true }
                        .keyboardShortcut("n", modifiers: .command)
                        .help("Start conversation")
                }
            }
        }
        .sheet(isPresented: $starting) {
            NavigationStack {
                StartConversationView(client: client) {
                    Task { await reload() }
                }
            }
            #if os(iOS)
            .presentationDetents([.medium, .large])
            #endif
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
        .task(id: client.view.active_profile_id) { await reload() }
        .onChange(of: client.view.navigation.revision) { _, _ in starting = false }
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
                }
            }
        }
    }

    private func row(_ thread: AppThread) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: thread.section == "archived" ? "archivebox"
                : thread.section == "in_progress" ? "circle.dotted" : "bubble.left")
                .foregroundStyle(thread.section == "in_progress" ? Noora.primary : Noora.labelSecondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: thread.title ?? thread.goal ?? "").font(.body.weight(.medium)).lineLimit(2)
                    .foregroundStyle(Noora.labelPrimary)
                Text(verbatim: [thread.repository, statusLabel(thread.state)]
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

    /// The personal account or organization whose threads this lists.
    private var account: String {
        client.view.accounts.first(where: \.selected)?.name ?? client.view.active?.handle ?? ""
    }

    private func run(cursor: String?) async {
        let task = Task { await fetch(cursor: cursor) }
        loading = task
        await task.value
        if loading == task { loading = nil }
    }

    private func fetch(cursor: String?) async {
        let profile = client.view.active_profile_id
        do {
            let data = try await client.call("threads", cursor.map { ["cursor": $0] } ?? [:])
            let page = try JSONDecoder().decode(ThreadPage.self, from: JSONSerialization.data(withJSONObject: data))
            // A newer load, or another profile, owns the list now.
            guard !Task.isCancelled, profile == client.view.active_profile_id else { return }
            threads = cursor == nil ? page.threads : threads + page.threads
            nextCursor = page.next_cursor
            available = page.available
            forbidden = page.reason == "forbidden"
            error = nil
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
        loaded = true
    }
}
