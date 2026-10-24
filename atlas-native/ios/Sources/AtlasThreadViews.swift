import AVFoundation
import Combine
import SwiftUI

struct AtlasOrbitView: View {
    let recordID: String?
    let revision: UUID?
    @StateObject private var model: AtlasOrbit
    @State private var path: [AtlasThread] = []
    @State private var creating = false
    @State private var openingPrivate = false
    @State private var openingLinkedThread = false
    @State private var linkedThreadID: String?
    @State private var handledRevision: UUID?
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
                    Section {
                        AtlasPipWelcome { prompt in Task { await openPrivateThread(prompt: prompt) } }
                            .disabled(model.creating || openingPrivate)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    if !assistant.configured {
                        Section {
                            Label {
                                Text("An administrator needs to configure the Orbit inference profile before the agent can reply.")
                            } icon: { Image(systemName: "info.circle") }
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Shared threads") {
                    let shared = model.threads.filter { $0.kind != "private" }
                    ForEach(shared) { thread in
                        NavigationLink(value: thread) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(thread.title).font(.headline)
                                if !thread.summary.isEmpty {
                                    Text(thread.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Text(thread.status.capitalized).font(.caption).foregroundStyle(.secondary)
                            }.frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("thread-\(thread.id)")
                    }
                    if shared.isEmpty, !model.loading, model.assistant != nil {
                        ContentUnavailableView("Work starts with a thread", systemImage: "bubble.left.and.bubble.right",
                                               description: Text("Start one with your team to investigate an issue or explore an idea."))
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
            .modifier(AtlasThemedContent())
            .overlay {
                if model.loading, model.assistant == nil { ProgressView("Loading threads") }
            }
            .defaultScrollAnchor(.top)
            .navigationTitle("Orbit")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom) {
                if let assistant = model.assistant {
                    Button { Task { await openPrivateThread() } } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Ask \(assistant.name)…").frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.up.right.circle.fill").font(.title2)
                        }
                        .frame(minHeight: 44).padding(.horizontal, 16).padding(.vertical, 4)
                        .background(Color(uiColor: .systemBackground), in: Capsule())
                        .overlay { Capsule().strokeBorder(Color(uiColor: .separator), lineWidth: 0.5) }
                    }
                    .buttonStyle(.plain).disabled(model.creating || openingPrivate)
                    .accessibilityHint("Opens your private thread with Pip.")
                    .accessibilityIdentifier("orbit-private")
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(.background)
                    .modifier(AtlasThemedContent())
                }
            }
            .navigationDestination(for: AtlasThread.self) { thread in
                AtlasThreadDetail(model: model, thread: thread, selfId: selfId)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New shared thread", systemImage: "square.and.pencil") { creating = true }
                        .disabled(model.assistant == nil).accessibilityIdentifier("orbit-create")
                }
            }
            .refreshable { await model.load() }
            .onAppear { presence?.show() }
            .sheet(isPresented: $creating) {
                AtlasCreateThread(model: model, people: presence?.people ?? []) { thread in
                    creating = false
                    path.append(thread)
                }
            }
        }
        .toolbar(path.isEmpty ? .visible : .hidden, for: .tabBar)
        .overlay {
            if openingLinkedThread {
                ProgressView("Opening thread…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground).opacity(0.95))
            }
        }
        .task(id: revision) {
            if let revision, revision != handledRevision {
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

    private func openPrivateThread(prompt: String? = nil) async {
        guard !openingPrivate else { return }
        openingPrivate = true
        defer { openingPrivate = false }
        if let thread = await model.privateThread() {
            linkedThreadID = nil
            if let prompt { model.draft += (model.draft.isEmpty ? "" : "\n\n") + prompt }
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

private struct AtlasThreadDetail: View {
    @ObservedObject var model: AtlasOrbit
    let thread: AtlasThread
    let selfId: String?
    @State private var addressAgent = false
    @State private var followLatest = true
    @State private var hasShownMessages = false
    @State private var showingInfo = false
    @StateObject private var voice = AtlasVoiceInput()
    @State private var startingVoice: Task<Void, Never>?
    @State private var photosPresented = false
    @State private var filesPresented = false
    @State private var attachmentError: String?
    @State private var previewURL: URL?
    @State private var openingAttachment: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.atlasPresence) private var presence

    private var assistantName: String { model.assistant?.name ?? "Pip" }
    private var current: AtlasThread { model.selected ?? thread }
    private var showsWelcome: Bool {
        thread.kind == "private" && model.selected?.id == thread.id && model.messages.isEmpty
            && !model.loadingHistory && model.errorMessage == nil
            && !["queued", "running", "compacting"].contains(current.agentStatus ?? "")
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if model.hasOlder {
                            Button("Load earlier messages") { followLatest = false; Task { await model.history(older: true) } }
                                .disabled(model.loadingHistory).frame(minHeight: 44)
                        }
                        if thread.kind == "private" {
                            Label("Private · Only you and \(assistantName)", systemImage: "lock")
                                .font(.caption).foregroundStyle(.secondary).padding(.vertical, 12)
                            if showsWelcome {
                                AtlasPipWelcome { prompt in
                                    model.draft += (model.draft.isEmpty ? "" : "\n\n") + prompt
                                }
                            }
                        }
                        AtlasThreadTimeline(messages: model.messages, selfId: selfId, openAttachment: openAttachment) { id, event in
                            await model.componentAction(messageId: id, event: event)
                        }
                        if let activity = model.activityMessage {
                            AtlasThreadActivity(message: activity,
                                                typing: model.selected?.agentStatus == "running" && model.activeToolName == nil)
                        }
                        if model.loadingHistory { ProgressView("Loading history") }
                        if let error = model.errorMessage {
                            Text(error).font(.callout).foregroundStyle(.red)
                            Button("Retry") { Task { await model.history() } }.frame(minHeight: 44)
                        }
                        Color.clear.frame(height: model.messages.isEmpty ? 1 : 49).id("thread-latest")
                            .background {
                                GeometryReader { position in
                                    Color.clear.preference(key: AtlasThreadBottom.self,
                                                           value: position.frame(in: .named("thread-history")).maxY)
                                }
                            }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: showsWelcome ? .top : .bottom)
                }
                .coordinateSpace(name: "thread-history")
                .onPreferenceChange(AtlasThreadBottom.self) { bottom in
                    followLatest = bottom.isFinite && bottom >= 0 && bottom <= geometry.size.height + 20
                }
                .defaultScrollAnchor(showsWelcome ? .top : .bottom)
                .scrollDismissesKeyboard(.interactively)
                .modifier(AtlasThemedContent())
                .refreshable { await model.history() }
                .onChange(of: model.messages.last?.id) { _, latest in
                    guard latest != nil else { return }
                    if !hasShownMessages || followLatest { scroll.scrollTo("thread-latest", anchor: .bottom) }
                    hasShownMessages = true
                }
                .onChange(of: model.activityMessage) { _, _ in
                    if followLatest { scroll.scrollTo("thread-latest", anchor: .bottom) }
                }
                .overlay(alignment: .bottomTrailing) {
                    AtlasThreadNavigation(messages: model.messages, shared: thread.kind != "private",
                                          hasOlder: model.hasOlder, loading: model.loadingHistory,
                                          showsLatest: !followLatest && !showsWelcome && !model.messages.isEmpty,
                                          older: { followLatest = false; await model.history(older: true) }, jump: { id in
                        followLatest = id == "thread-latest"
                        scroll.scrollTo(id, anchor: followLatest ? .bottom : .top)
                    })
                    .padding()
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .navigationTitle(thread.kind == "private" ? assistantName : thread.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Thread details", systemImage: "info.circle") { showingInfo = true }
                    .accessibilityIdentifier("thread-info")
            }
        }
        .sheet(isPresented: $showingInfo) { details }
        .modifier(AtlasAttachmentPicker(photosPresented: $photosPresented, filesPresented: $filesPresented, upload: { file in
            guard !Task.isCancelled, model.selected?.id == thread.id else { return }
            await model.upload(filename: file.filename, contentType: file.contentType, data: file.data)
        }, failure: { attachmentError = $0 }))
        .modifier(AtlasAttachmentPreview(url: $previewURL))
        .alert("Attachment could not be opened", isPresented: Binding(get: { attachmentError != nil }, set: {
            if !$0 { attachmentError = nil }
        })) { Button("OK", role: .cancel) { attachmentError = nil } } message: { Text(attachmentError ?? "") }
        .task(id: thread.id) { presence?.show(); await model.open(thread) }
        .onDisappear { startingVoice?.cancel(); openingAttachment?.cancel(); voice.cancel(); model.leave(id: thread.id) }
        .onChange(of: scenePhase) { _, phase in
            // Permission alerts temporarily deactivate the scene before their callbacks return.
            if phase == .background || (phase == .inactive && voice.phase != .requesting) {
                startingVoice?.cancel()
                voice.cancel()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in
            startingVoice?.cancel()
            voice.cancel()
        }
        .protectsAtlasNavigation(!model.draft.isEmpty || !model.draftAttachments.isEmpty || model.pendingUploadName != nil
            || model.saving || model.attachmentBusy || voice.busy)
    }

    private func openAttachment(_ attachment: AtlasThreadAttachment) {
        openingAttachment?.cancel()
        openingAttachment = Task {
            guard let data = await model.download(attachment), !Task.isCancelled else { return }
            do { previewURL = try AtlasAttachmentFile.preview(data, filename: attachment.filename) } catch {
                attachmentError = error.localizedDescription
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = model.liveMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            } else {
                let viewers = model.viewers.filter { $0.id != selfId }
                if !viewers.isEmpty {
                    Text(viewers.map { $0.name + ($0.typing ? " is typing…" : " is here") }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("thread-presence")
                }
            }
            if thread.kind != "private" {
                Button { addressAgent.toggle() } label: {
                    Label("Ask \(assistantName)", systemImage: addressAgent ? "checkmark.circle.fill" : "sparkles")
                        .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityValue(addressAgent ? "On" : "Off")
                .accessibilityIdentifier("thread-address-agent")
            }
            if let error = voice.errorMessage {
                Text(error).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("thread-voice-error")
            }
            AtlasDraftAttachments(model: model, open: openAttachment)
            AtlasThreadComposer(draft: Binding(get: { model.draft }, set: { model.draft = $0 }),
                                placeholder: thread.kind == "private" ? "Ask \(assistantName)" : "Message the team",
                                saving: model.saving || model.attachmentBusy || model.pendingUploadName != nil, phase: voice.phase,
                                transcript: voice.transcript, levels: voice.levels, hasAttachments: !model.draftAttachments.isEmpty,
                                addPhotos: { photosPresented = true }, addFiles: { filesPresented = true },
                                start: { startingVoice = Task { await voice.start() } }, review: {
                startingVoice?.cancel()
                voice.review()
            }, cancel: {
                startingVoice?.cancel()
                voice.cancel()
            }, accept: {
                voice.finish { text in model.draft = AtlasVoiceInput.appending(text, to: model.draft) }
            }, send: {
                followLatest = true
                Task { await model.send(addressAgent: addressAgent) }
            })
            .disabled(model.selected?.id != thread.id)
        }
        .frame(maxWidth: 688).padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
        .frame(maxWidth: .infinity)
    }

    private var details: some View {
        NavigationStack {
            Form {
                Section("Thread") {
                    if current.kind == "private" { Label("Only you and \(assistantName)", systemImage: "lock") }
                    if !current.summary.isEmpty { Text(current.summary) }
                    if !current.origin.isEmpty { LabeledContent("Started from", value: current.origin.capitalized) }
                    LabeledContent("Status", value: current.status.capitalized)
                }
                if current.kind != "private" {
                    Section("Participants") { ForEach(current.participants) { Text($0.name) } }
                }
            }
            .navigationTitle("Thread details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingInfo = false } } }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct AtlasThreadBottom: PreferenceKey {
    static var defaultValue: CGFloat { .infinity }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
