import Combine
import SwiftUI

struct AtlasOrbitView: View {
    let recordID: String?
    let revision: UUID?
    @StateObject private var model: AtlasOrbit
    @State private var path: [AtlasThread] = []
    @State private var openingPrivate = false
    @State private var openingLinkedThread = false
    @State private var linkedThreadID: String?
    @State private var handledRevision: UUID?
    @State private var navigationIntent = UUID()
    @State private var selfId: String?
    @State private var confirmingArchive: AtlasThread?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.atlasPresence) private var presence

    init(recordID: String? = nil, revision: UUID? = nil, request: @escaping ([String: Any]) async throws -> Data,
         localRequest: @escaping ([String: Any]) async throws -> Data) {
        self.recordID = recordID
        self.revision = revision
        _model = StateObject(wrappedValue: AtlasOrbit(request: request, localRequest: localRequest))
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Picker("Conversations", selection: Binding(get: { model.statusFilter }, set: { status in
                        Task { await model.load(status: status) }
                    })) {
                        Text("Active").tag("active")
                        Text("Archived").tag("archived")
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.loading || model.saving)
                    .accessibilityIdentifier("orbit-status")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                if let assistant = model.assistant {
                    if !assistant.configured {
                        Section {
                            Label {
                                Text("Connect an AI account in Profile, or ask an administrator to configure Pip.")
                            } icon: { Image(systemName: "info.circle") }
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(conversationSections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.threads) { thread in conversationRow(thread) }
                    }
                    .textCase(nil)
                }
                if model.threads.isEmpty, !model.loading, model.assistant != nil {
                    ContentUnavailableView(model.statusFilter == "archived" ? "No archived conversations" : "Your conversations with Pip",
                                           systemImage: model.statusFilter == "archived" ? "archivebox" : "bubble.left.and.bubble.right",
                                           description: Text(model.statusFilter == "archived"
                                               ? "Archived conversations stay here until you restore them."
                                               : "Start a conversation using the compose button above."))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if model.hasMore {
                    HStack {
                        Button("Load more") { Task { await model.load(more: true) } }.disabled(model.loading)
                        if model.loading { ProgressView().accessibilityLabel("Loading more threads") }
                    }
                }
                if let error = model.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red)
                        Button("Retry") {
                            Task {
                                if let linkedThreadID { await openLinkedThread(id: linkedThreadID) } else { await model.load() }
                            }
                        }.disabled(model.loading || openingLinkedThread)
                    }
                }
            }
            .listStyle(.plain)
            .modifier(AtlasThemedContent())
            .overlay {
                if model.loading, model.assistant == nil { ProgressView("Loading threads") }
            }
            .defaultScrollAnchor(.top)
            .navigationTitle("Orbit")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: AtlasThread.self) { thread in
                AtlasThreadDetail(model: model, thread: thread, selfId: selfId)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New conversation", systemImage: "square.and.pencil") {
                        Task { await openPrivateThread() }
                    }
                    .disabled(model.assistant == nil || model.creating || openingPrivate)
                    .accessibilityIdentifier("orbit-create")
                }
            }
            .refreshable { await model.load() }
            .onAppear { presence?.show() }
        }
        .confirmationDialog("Archive this shared conversation?", isPresented: Binding(
            get: { confirmingArchive != nil }, set: { if !$0 { confirmingArchive = nil } }
        ), titleVisibility: .visible, presenting: confirmingArchive) { thread in
            Button("Archive conversation") { Task { await model.archive(thread, archived: true) } }
        } message: { _ in
            Text("It will become read-only for everyone. You can restore it from Archived.")
        }
        .toolbar(path.isEmpty ? .visible : .hidden, for: .tabBar)
        .overlay {
            if openingLinkedThread || openingPrivate {
                ProgressView(openingPrivate ? "Starting conversation…" : "Opening thread…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground).opacity(0.95))
            }
        }
        .task(id: revision) {
            if let revision, revision != handledRevision {
                navigationIntent = UUID()
                if let recordID {
                    linkedThreadID = recordID
                    await openLinkedThread(id: recordID)
                } else {
                    path = []
                    linkedThreadID = nil
                    await model.load()
                }
                if !Task.isCancelled { handledRevision = revision }
            } else if model.assistant == nil {
                await model.load()
            }
        }
        .onReceive(presence?.$selfId.eraseToAnyPublisher() ?? Just(nil).eraseToAnyPublisher()) { selfId = $0 }
        .onAppear { model.setActive(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in model.setActive(phase == .active) }
        .onDisappear { model.setActive(false) }
    }

    private var conversationSections: [(title: String, threads: [AtlasThread])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: model.threads) { thread in
            guard let date = thread.updatedDate else { return "Earlier" }
            if calendar.isDateInToday(date) { return "Today" }
            return calendar.isDateInYesterday(date) ? "Yesterday" : "Earlier"
        }
        return ["Today", "Yesterday", "Earlier"].compactMap { title in
            groups[title].map { (title: title, threads: $0) }
        }
    }

    private func conversationRow(_ thread: AtlasThread) -> some View {
        Button { path.append(thread) } label: {
            VStack(alignment: .leading, spacing: 7) {
                Text(thread.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                if !thread.summary.isEmpty {
                    Text(thread.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 10) {
                    Label(thread.kind == "private" ? "Private" : "Shared", systemImage: thread.kind == "private" ? "lock" : "person.2")
                    if ["queued", "running", "compacting"].contains(thread.agentStatus ?? "") {
                        Label("Working", systemImage: "sparkles")
                    }
                    Spacer(minLength: 0)
                    if let date = thread.updatedDate {
                        if Calendar.current.isDateInToday(date) {
                            Text(date, format: .dateTime.hour().minute())
                        } else {
                            Text(date, format: .dateTime.month(.abbreviated).day().year())
                        }
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("thread-\(thread.id)")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let selfId, thread.ownerId == selfId { archiveAction(thread) }
        }
        .contextMenu {
            if let selfId, thread.ownerId == selfId { archiveAction(thread) }
        }
    }

    private func archiveAction(_ thread: AtlasThread) -> some View {
        Button(thread.status == "archived" ? "Restore" : "Archive",
               systemImage: thread.status == "archived" ? "tray.and.arrow.up" : "archivebox") {
            if thread.kind != "private", thread.status != "archived" {
                confirmingArchive = thread
            } else {
                Task { await model.archive(thread, archived: thread.status != "archived") }
            }
        }
        .tint(.orange)
        .disabled(model.saving || model.loading)
    }

    private func openPrivateThread() async {
        guard !openingPrivate else { return }
        let intent = navigationIntent
        openingPrivate = true
        defer { openingPrivate = false }
        if let thread = await model.newPrivateThread(), !Task.isCancelled, navigationIntent == intent {
            linkedThreadID = nil
            path.append(thread)
        }
    }

    private func openLinkedThread(id: String) async {
        openingLinkedThread = true
        defer { if !Task.isCancelled { openingLinkedThread = false } }
        let thread = await model.open(id: id)
        guard !Task.isCancelled else { return }
        path = thread.map { [$0] } ?? []
        if thread != nil { linkedThreadID = nil }
    }
}
