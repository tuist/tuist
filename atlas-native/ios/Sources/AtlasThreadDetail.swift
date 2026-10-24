import AVFoundation
import Combine
import SwiftUI

struct AtlasThreadDetail: View {
    @ObservedObject var model: AtlasOrbit
    let thread: AtlasThread
    let selfId: String?
    @State private var addressAgent = false
    @State private var followLatest = true
    @State private var scrollMetrics: AtlasThreadScrollMetrics?
    @State private var scrollBaseline: CGFloat?
    @State private var visibleMessageID: String?
    @State private var jumpingToPrompt = false
    @State private var hasShownMessages = false
    @State private var openingHistory = true
    @State private var pagingHistory = false
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.atlasTheme) private var theme
    @Environment(\.colorScheme) private var scheme

    private var assistantName: String { model.assistant?.name ?? "Pip" }
    private var current: AtlasThread { model.selected ?? thread }
    private var showsWelcome: Bool {
        thread.kind == "private" && model.selected?.id == thread.id && model.messages.isEmpty
            && !openingHistory && !model.loadingHistory && model.errorMessage == nil
            && !["queued", "running", "compacting"].contains(current.agentStatus ?? "")
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(spacing: 14) {
                        if model.hasOlder {
                            Button(model.loadingHistory || pagingHistory ? "Loading earlier messages…" : "Load earlier messages") {
                                Task { await loadEarlier() }
                            }
                                .disabled(model.loadingHistory || pagingHistory).frame(minHeight: 44)
                                .accessibilityIdentifier("thread-earlier")
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
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: showsWelcome ? .top : .bottom)
                    .background {
                        GeometryReader { content in
                            Color.clear.preference(key: AtlasThreadScrollPreference.self, value: AtlasThreadScrollMetrics(
                                height: content.size.height,
                                bottom: content.frame(in: .global).maxY - geometry.frame(in: .global).minY,
                                viewport: geometry.size.height))
                        }
                    }
                }
                .scrollPosition(id: $visibleMessageID)
                .modifier(AtlasThreadScrollObserver { metrics in
                    let previous = scrollMetrics
                    scrollMetrics = metrics
                    let atBottom = metrics.bottom >= 0 && metrics.bottom <= metrics.viewport + 20
                    // Content growth changes height and bottom equally; only scrolling changes their difference.
                    if previous?.viewport != metrics.viewport { scrollBaseline = metrics.offset }
                    let baseline = max(scrollBaseline ?? metrics.offset, metrics.offset)
                    let movedUp = metrics.offset < baseline - 1
                    scrollBaseline = movedUp ? metrics.offset : baseline
                    if !jumpingToPrompt, atBottom || movedUp { followLatest = atBottom }
                    if followLatest, !jumpingToPrompt, !showsWelcome, previous?.height != metrics.height {
                        scroll.scrollTo("thread-latest", anchor: .bottom)
                    }
                    if hasShownMessages, !followLatest, !jumpingToPrompt, metrics.offset < 240,
                       model.hasOlder, !model.loadingHistory, !pagingHistory, model.errorMessage == nil {
                        Task { await loadEarlier() }
                    }
                })
                .defaultScrollAnchor(showsWelcome ? .top : .bottom)
                .scrollDismissesKeyboard(.interactively)
                .modifier(AtlasThemedContent())
                .refreshable { await model.history() }
                .onChange(of: model.messages.last?.id, initial: true) { _, latest in
                    guard latest != nil else { return }
                    if !hasShownMessages || followLatest { scroll.scrollTo("thread-latest", anchor: .bottom) }
                    hasShownMessages = true
                }
                .onChange(of: model.activityMessage) { _, _ in
                    if followLatest { scroll.scrollTo("thread-latest", anchor: .bottom) }
                }
                .onChange(of: geometry.size.height) { _, _ in
                    if followLatest, !showsWelcome { scroll.scrollTo("thread-latest", anchor: .bottom) }
                }
                .overlay(alignment: .bottomTrailing) {
                    AtlasThreadNavigation(messages: model.messages, shared: thread.kind != "private",
                                          hasOlder: model.hasOlder, loading: model.loadingHistory,
                                          showsLatest: !followLatest && !showsWelcome && !model.messages.isEmpty,
                                          older: { await loadEarlier() }, jump: { id in
                        followLatest = id == "thread-latest"
                        jumpingToPrompt = true
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                            scroll.scrollTo(id, anchor: id == "thread-latest" ? .bottom : .top)
                        } completion: {
                            followLatest = id == "thread-latest"
                            jumpingToPrompt = false
                        }
                    })
                    .padding()
                }
                .overlay {
                    if openingHistory && model.messages.isEmpty {
                        ProgressView("Loading conversation…").accessibilityIdentifier("thread-history-loading")
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
        .modifier(AtlasAttachmentPicker(photosPresented: $photosPresented, filesPresented: $filesPresented, upload: { file in
            guard !Task.isCancelled, model.selected?.id == thread.id else { return }
            await model.upload(filename: file.filename, contentType: file.contentType, data: file.data)
        }, failure: { attachmentError = $0 }))
        .modifier(AtlasAttachmentPreview(url: $previewURL))
        .alert("Attachment could not be opened", isPresented: Binding(get: { attachmentError != nil }, set: {
            if !$0 { attachmentError = nil }
        })) { Button("OK", role: .cancel) { attachmentError = nil } } message: { Text(attachmentError ?? "") }
        .task(id: thread.id) {
            presence?.show()
            await model.open(thread)
            openingHistory = false
        }
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
}

extension AtlasThreadDetail {
    private func loadEarlier() async {
        guard !pagingHistory, !model.loadingHistory, model.hasOlder else { return }
        pagingHistory = true
        followLatest = false
        await model.history(older: true)
        pagingHistory = false
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
                                levels: voice.levels, hasAttachments: !model.draftAttachments.isEmpty,
                                addPhotos: { photosPresented = true }, addFiles: { filesPresented = true },
                                start: { startingVoice = Task { await voice.start() } }, stop: {
                startingVoice?.cancel()
                voice.finish { text in
                    guard model.selected?.id == thread.id else { return }
                    model.draft = AtlasVoiceInput.appending(text, to: model.draft)
                }
            }, cancel: {
                startingVoice?.cancel()
                voice.cancel()
            }, send: {
                followLatest = true
                Task { await model.send(addressAgent: addressAgent) }
            })
            .disabled(model.selected?.id != thread.id)
        }
        .frame(maxWidth: 688).padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background {
            (theme.map { Color(atlasHex: $0.palette(scheme).background) } ?? Color(uiColor: .systemBackground))
                .ignoresSafeArea(edges: .bottom)
        }
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

private struct AtlasThreadScrollMetrics: Equatable {
    let height: CGFloat
    let bottom: CGFloat
    let viewport: CGFloat
    var offset: CGFloat { height - bottom }
}

private struct AtlasThreadScrollPreference: PreferenceKey {
    static var defaultValue: AtlasThreadScrollMetrics? { nil }
    static func reduce(value: inout AtlasThreadScrollMetrics?, nextValue: () -> AtlasThreadScrollMetrics?) { value = nextValue() }
}

private struct AtlasThreadScrollObserver: ViewModifier {
    let update: (AtlasThreadScrollMetrics) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: AtlasThreadScrollMetrics.self) { geometry in
                AtlasThreadScrollMetrics(height: geometry.contentSize.height,
                                         bottom: geometry.contentSize.height - geometry.contentOffset.y,
                                         viewport: geometry.containerSize.height)
            } action: { _, metrics in
                update(metrics)
            }
        } else {
            content.onPreferenceChange(AtlasThreadScrollPreference.self) { metrics in
                if let metrics { update(metrics) }
            }
        }
    }
}
