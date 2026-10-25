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
                Section {
                    let conversations = model.threads
                    ForEach(conversations) { thread in
                        Button { path.append(thread) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(thread.title).font(.body).foregroundStyle(.primary).lineLimit(2)
                                HStack(spacing: 8) {
                                    if thread.kind != "private" { Label("Shared", systemImage: "person.2") }
                                    if let date = thread.updatedDate { Text(date, style: .relative) }
                                }
                                .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .accessibilityIdentifier("thread-\(thread.id)")
                    }
                    if conversations.isEmpty, !model.loading, model.assistant != nil {
                        ContentUnavailableView("Your conversations with Pip", systemImage: "bubble.left.and.bubble.right",
                                               description: Text("Start a conversation using the compose button above."))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    if model.hasMore {
                        HStack {
                            Button("Load more") { Task { await model.load(more: true) } }.disabled(model.loading)
                            if model.loading { ProgressView().accessibilityLabel("Loading more threads") }
                        }
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
