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
    @State private var showingThreadInfo = false
    @State private var search = ""
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.atlasPresence) private var presence
    @Environment(\.atlasNavigation) private var workspaceNavigation
    #if os(iOS)
    @Environment(\.atlasLiveActivity) private var liveActivity
    #elseif os(macOS)
    @Environment(\.atlasEnvironmentRequest) private var environmentRequest
    #endif

    init(recordID: String? = nil, revision: UUID? = nil, request: @escaping ([String: Any]) async throws -> Data,
         localRequest: @escaping ([String: Any]) async throws -> Data) {
        self.recordID = recordID
        self.revision = revision
        _model = StateObject(wrappedValue: AtlasOrbit(request: request, localRequest: localRequest))
    }

    init(model: AtlasOrbit, recordID: String? = nil, revision: UUID? = nil) {
        self.recordID = recordID
        self.revision = revision
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        navigation
        .confirmationDialog("Archive this shared conversation?", isPresented: Binding(
            get: { confirmingArchive != nil }, set: { if !$0 { confirmingArchive = nil } }
        ), titleVisibility: .visible, presenting: confirmingArchive) { thread in
            Button("Archive conversation") { Task { await model.archive(thread, archived: true) } }
        } message: { _ in
            Text("It will become read-only for everyone. You can restore it from Archived.")
        }
        #if os(iOS)
        .toolbar(path.isEmpty ? .visible : .hidden, for: .tabBar)
        #endif
        .overlay {
            if openingLinkedThread || openingPrivate {
                ProgressView(openingPrivate ? "Starting conversation…" : "Opening thread…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(loadingBackground.opacity(0.95))
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
        #if os(iOS)
        .onReceive(model.workChanges) { liveActivity?.refresh() }
        #endif
        .onAppear { model.setActive(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in model.setActive(phase == .active) }
        .onDisappear { model.setActive(false) }
    }

    @ViewBuilder private var navigation: some View {
        #if os(macOS)
        NavigationStack {
            GeometryReader { geometry in
                HSplitView {
                    inbox.frame(minWidth: 240, idealWidth: 300, maxWidth: 380)
                    Group {
                        if let thread = path.last {
                            AtlasThreadDetail(model: model, thread: thread, selfId: selfId)
                        } else {
                            ContentUnavailableView("No conversation selected", systemImage: "bubble.left.and.bubble.right",
                                                   description: Text("Select a conversation or start a new one."))
                        }
                    }
                    .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .navigationTitle(desktopThread.map { $0.kind == "private" ? (model.assistant?.name ?? "Pip") : $0.title } ?? "Orbit")
        .navigationSubtitle(desktopThread.map {
            $0.kind == "private" ? "Private · Only you and \(model.assistant?.name ?? "Pip")" : "Shared conversation"
        } ?? "")
        .toolbar {
            ToolbarItem(id: "orbit-status", placement: .primaryAction) {
                statusPicker.labelsHidden().frame(width: 170)
            }
            ToolbarItem(id: "orbit-create", placement: .primaryAction) { composeButton }
            ToolbarItem(placement: .primaryAction) { AtlasOrbitDomainFilter(model: model) }
            ToolbarItem(id: "orbit-environment", placement: .primaryAction) {
                if let thread = desktopThread, thread.kind == "private", thread.status == "active", let environmentRequest {
                    AtlasEnvironmentPicker(threadId: thread.id, request: environmentRequest).id(thread.id)
                } else {
                    Button("Tool environment", systemImage: "desktopcomputer") {}.disabled(true)
                }
            }
            ToolbarItem(id: "thread-info", placement: .primaryAction) {
                Button("Thread details", systemImage: "info.circle") { showingThreadInfo = true }
                    .disabled(desktopThread == nil).accessibilityIdentifier("thread-info")
            }
        }
        .sheet(isPresented: $showingThreadInfo) {
            if let thread = desktopThread {
                AtlasThreadInfo(thread: thread, assistantName: model.assistant?.name ?? "Pip")
            }
        }
        #else
        NavigationStack(path: $path) {
            inbox.navigationDestination(for: AtlasThread.self) { thread in
                AtlasThreadDetail(model: model, thread: thread, selfId: selfId)
            }
        }
        #endif
    }

    private var inbox: some View {
        Group {
            #if os(macOS)
            List(selection: desktopSelection) { inboxRows }
                .listStyle(.inset)
            #else
            List { inboxRows }.listStyle(.plain)
            #endif
        }
        #if os(iOS)
        .safeAreaInset(edge: .top, spacing: 0) {
            statusPicker.padding(.horizontal, 16).padding(.vertical, 8)
        }
        #endif
        .modifier(AtlasThemedContent())
        .overlay {
            if model.loading, model.assistant == nil { ProgressView("Loading threads") }
        }
        .defaultScrollAnchor(.top)
        .modifier(AtlasOrbitSearch(text: $search, enabled: model.assistant?.searchable == true && !model.cached))
        .task(id: search) {
            guard model.assistant?.searchable == true, !model.cached, search != model.query else { return }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await model.load(query: search)
        }
        #if os(iOS)
        .navigationTitle("Orbit")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { AtlasOrbitDomainFilter(model: model) }
            ToolbarItem(placement: .primaryAction) { composeButton }
        }
        #endif
        .refreshable { await model.load() }
        .onAppear { presence?.show(); search = model.query }
    }

    private var composeButton: some View {
        Button("New conversation", systemImage: "square.and.pencil") {
            Task { await openPrivateThread() }
        }
        .disabled(model.cached || model.assistant == nil || model.creating || openingPrivate)
        .accessibilityIdentifier("orbit-create")
        #if os(macOS)
        .keyboardShortcut("n")
        #endif
    }
}

extension AtlasOrbitView {
    @ViewBuilder private var inboxRows: some View {
        if model.cached, model.errorMessage != nil, linkedThreadID == nil {
            HStack {
                Text("Couldn’t refresh").foregroundStyle(.secondary)
                    .accessibilityIdentifier("orbit-refresh-error")
                Spacer()
                Button { Task { await model.load() } } label: {
                    Text("Retry").frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.borderless)
                    .disabled(model.loading)
                    .accessibilityIdentifier("orbit-refresh-retry")
            }
            .font(.footnote)
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
            Section {
                ForEach(section.threads) { thread in conversationRow(thread) }
            } header: {
                if !section.title.isEmpty { Text(section.title) }
            }
            .textCase(nil)
        }
        if model.threads.isEmpty, !model.loading, model.assistant != nil {
            ContentUnavailableView(!model.query.isEmpty || !model.domainFilter.isEmpty ? "No matching conversations"
                                       : model.statusFilter == "archived" ? "No archived conversations" : "Your conversations with Pip",
                                   systemImage: model.statusFilter == "archived" ? "archivebox" : "bubble.left.and.bubble.right",
                                   description: Text(!model.query.isEmpty || !model.domainFilter.isEmpty
                                       ? "Try another search or choose All domains."
                                       : model.statusFilter == "archived"
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
        if let error = model.errorMessage, !model.cached || linkedThreadID != nil {
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

    private var statusPicker: some View {
        Picker("Conversations", selection: Binding(get: { model.statusFilter }, set: { status in
            Task { await model.load(status: status) }
        })) {
            Text("Active").tag("active")
            Text("Archived").tag("archived")
        }
        .pickerStyle(.segmented)
        .disabled(model.loading || model.saving)
        .accessibilityIdentifier("orbit-status")
    }

    private var loadingBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    private var conversationSections: [(title: String, threads: [AtlasThread])] {
        let calendar = Calendar.current
        #if os(iOS)
        let signals = model.threads.filter { $0.priorityTitle != nil }
        let attention: [(title: String, threads: [AtlasThread])] = signals.isEmpty ? [] : [(title: "", threads: signals)]
        #else
        let attention = ["Now", "Today", "Later"].compactMap { priority -> (title: String, threads: [AtlasThread])? in
            let threads = model.threads.filter { $0.priorityTitle == priority }
            return threads.isEmpty ? nil : (title: "\(priority) · Signals", threads: threads)
        }
        #endif
        let groups = Dictionary(grouping: model.threads.filter { $0.priorityTitle == nil }) { thread in
            guard let date = thread.updatedDate else { return "Earlier" }
            if calendar.isDateInToday(date) { return "Today" }
            return calendar.isDateInYesterday(date) ? "Yesterday" : "Earlier"
        }
        return attention + ["Today", "Yesterday", "Earlier"].compactMap { title in
            groups[title].map { (title: title, threads: $0) }
        }
    }

    private func conversationRow(_ thread: AtlasThread) -> some View {
        Group {
            #if os(macOS)
            AtlasDesktopConversationRow(thread: thread)
            #else
            NavigationLink(value: thread) { AtlasMobileConversationRow(thread: thread, domainTitle: model.domainTitle(thread.domain)) }
            #endif
        }
        #if os(macOS)
        .tag(thread.id)
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        .listRowSeparator(.hidden)
        #else
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        #endif
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
        .disabled(model.cached || model.saving || model.loading)
    }

    private func openPrivateThread() async {
        guard !openingPrivate else { return }
        #if os(macOS)
        guard canChangeConversation else { return }
        #endif
        let intent = navigationIntent
        openingPrivate = true
        defer { openingPrivate = false }
        if let thread = await model.newPrivateThread(), !Task.isCancelled, navigationIntent == intent {
            linkedThreadID = nil
            #if os(macOS)
            path = [thread]
            #else
            path.append(thread)
            #endif
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

    #if os(macOS)
    private var desktopThread: AtlasThread? {
        guard let thread = path.last else { return nil }
        return model.selected?.id == thread.id ? model.selected : thread
    }

    private var desktopSelection: Binding<String?> {
        Binding(get: { path.last?.id }, set: { id in
            guard id != path.last?.id, canChangeConversation else { return }
            path = id.flatMap { id in model.threads.first { $0.id == id } }.map { [$0] } ?? []
        })
    }

    private var canChangeConversation: Bool {
        guard workspaceNavigation?.hasProtectedWork == true else { return true }
        workspaceNavigation?.message = "Finish or discard your changes before switching conversations."
        return false
    }
    #endif
}
