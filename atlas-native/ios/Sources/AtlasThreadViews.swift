import AVFoundation
import Combine
import SwiftUI

struct AtlasOrbitView: View {
    @StateObject private var model: AtlasOrbit
    @State private var path: [AtlasThread] = []
    @State private var creating = false
    @State private var selfId: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.atlasPresence) private var presence

    init(request: @escaping ([String: Any]) async throws -> Data,
         localRequest: @escaping ([String: Any]) async throws -> Data) {
        _model = StateObject(wrappedValue: AtlasOrbit(request: request, localRequest: localRequest))
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let assistant = model.assistant {
                    Section {
                        Button {
                            Task { if let thread = await model.privateThread() { path.append(thread) } }
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(assistant.name).font(.headline)
                                    Text("Your private thread").font(.subheadline).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: "sparkles") }
                            .frame(minHeight: 44)
                        }
                        .disabled(model.creating)
                        .accessibilityIdentifier("orbit-private")
                        if !assistant.configured {
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
                        Button("Retry") { Task { await model.load() } }.disabled(model.loading)
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
            .navigationDestination(for: AtlasThread.self) { thread in
                AtlasThreadDetail(model: model, thread: thread, selfId: selfId)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New shared thread", systemImage: "square.and.pencil") { creating = true }
                        .disabled(model.assistant == nil).accessibilityIdentifier("orbit-create")
                }
            }
            .task { if model.assistant == nil { await model.load() } }
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
        .onReceive(presence?.$selfId.eraseToAnyPublisher() ?? Just(nil).eraseToAnyPublisher()) { selfId = $0 }
        .onAppear { model.setActive(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in model.setActive(phase == .active) }
        .onDisappear { model.setActive(false) }
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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.atlasPresence) private var presence

    private var assistantName: String { model.assistant?.name ?? "Pip" }
    private var current: AtlasThread { model.selected ?? thread }

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
                        }
                        ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                            if startsDay(at: index), let date = ISO8601DateFormatter().date(from: message.insertedAt) {
                                Text(date, format: .dateTime.month(.abbreviated).day().year())
                                    .font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.vertical, 8)
                            }
                            AtlasThreadMessageView(message: message, selfId: selfId) { event in
                                await model.componentAction(messageId: message.id, event: event)
                            }
                            .id(message.id)
                        }
                        if let activity = model.activityMessage {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small).accessibilityHidden(true)
                                Text(activity).font(.callout).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("thread-agent-activity")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                        }
                        if model.loadingHistory { ProgressView("Loading history") }
                        if let error = model.errorMessage {
                            Text(error).font(.callout).foregroundStyle(.red)
                            Button("Retry") { Task { await model.history() } }.frame(minHeight: 44)
                        }
                        Color.clear.frame(height: 1).id("thread-latest")
                            .background {
                                GeometryReader { position in
                                    Color.clear.preference(key: AtlasThreadBottom.self,
                                                           value: position.frame(in: .named("thread-history")).maxY)
                                }
                            }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .bottom)
                }
                .coordinateSpace(name: "thread-history")
                .onPreferenceChange(AtlasThreadBottom.self) { bottom in
                    followLatest = bottom.isFinite && bottom >= 0 && bottom <= geometry.size.height + 20
                }
                .defaultScrollAnchor(.bottom)
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
                    if !followLatest {
                        Button("Latest messages", systemImage: "arrow.down") {
                            followLatest = true
                            scroll.scrollTo("thread-latest", anchor: .bottom)
                        }
                        .labelStyle(.iconOnly).buttonStyle(.borderedProminent)
                        .frame(minWidth: 44, minHeight: 44).padding()
                    }
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
        .task(id: thread.id) { presence?.show(); await model.open(thread) }
        .onDisappear { startingVoice?.cancel(); voice.cancel(); model.leave(id: thread.id) }
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
        .protectsAtlasNavigation(!model.draft.isEmpty || model.saving || voice.busy)
    }

    private func startsDay(at index: Int) -> Bool {
        guard index > 0,
              let date = ISO8601DateFormatter().date(from: model.messages[index].insertedAt),
              let previous = ISO8601DateFormatter().date(from: model.messages[index - 1].insertedAt) else { return true }
        return !Calendar.current.isDate(date, inSameDayAs: previous)
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
            if voice.busy {
                AtlasVoiceInputView(phase: voice.phase, transcript: voice.transcript, levels: voice.levels,
                                    cancel: voice.cancel) {
                    voice.finish { text in model.draft = AtlasVoiceInput.appending(text, to: model.draft) }
                }
            }
            textComposer
        }
        .frame(maxWidth: 688).padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
        .frame(maxWidth: .infinity).background(.bar)
    }

    private var textComposer: some View {
        HStack(alignment: .bottom, spacing: 8) {
                TextField(thread.kind == "private" ? "Message \(assistantName)" : "Message the team",
                          text: Binding(get: { model.draft }, set: { model.draft = $0 }), axis: .vertical)
                    .lineLimit(1...6).textFieldStyle(.plain).padding(.leading, 12).padding(.vertical, 12)
                    .disabled(voice.busy)
                    .accessibilityIdentifier("thread-composer")
                AtlasMicrophoneButton(active: voice.phase == .requesting || voice.phase == .recording, start: {
                    startingVoice = Task { await voice.start() }
                }, review: {
                    startingVoice?.cancel()
                    voice.review()
                })
                    .disabled(model.saving || voice.phase == .reviewing || voice.phase == .finishing)
                Button {
                    followLatest = true
                    Task { await model.send(addressAgent: addressAgent) }
                } label: {
                    Group {
                        if model.saving { ProgressView() } else { Image(systemName: "arrow.up").font(.headline.bold()) }
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(AtlasComposerSendStyle())
                .accessibilityLabel("Send message")
                .disabled(voice.busy || model.saving || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("thread-send")
            }
            .padding(6).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 28))
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

private struct AtlasComposerSendStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.atlasTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let onAccent = contrast == .increased ? Color(uiColor: .systemBackground)
            : theme.map { Color(atlasHex: $0.palette(scheme).onAccent) } ?? AtlasSettingsStyle.onTint
        configuration.label
            .foregroundStyle(onAccent)
            .background { Circle().fill(.tint).padding(4) }
            .contentShape(Rectangle())
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.3)
    }
}

private struct AtlasThreadBottom: PreferenceKey {
    static var defaultValue: CGFloat { .infinity }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
