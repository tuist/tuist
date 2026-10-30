import AVFoundation
import Combine
import SwiftUI

struct AtlasThreadDetail: View {
    @ObservedObject var model: AtlasOrbit
    let thread: AtlasThread
    let selfId: String?
    @StateObject private var scrolling = AtlasThreadScrollState()
    @State private var visibleMessageID: String?
    @State private var scrollAnchor = UnitPoint.bottom
    @State private var jumpingToPrompt = false
    @State private var hasShownMessages = false
    @State private var openingHistory = true
    @State private var pagingHistory = false
    @State private var showingInfo = false
    @State private var showingEnvironment = false
    @State private var showingModels = false
    @State private var confirmingShare = false
    @FocusState private var editing: Bool
    @StateObject private var voice = AtlasVoiceInput()
    @State private var startingVoice: Task<Void, Never>?
    @State private var photosPresented = false
    @State private var filesPresented = false
    @State private var attachmentError: String?
    @State private var previewURL: URL?
    @State private var openingAttachment: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.atlasPresence) private var presence
    @Environment(\.atlasEnvironmentRequest) private var environmentRequest
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var assistantName: String { model.assistant?.name ?? "Pip" }
    private var selectionMatches: Bool { model.selected?.id == thread.id }
    private var current: AtlasThread {
        if let selected = model.selected, selected.id == thread.id { return selected }
        return thread
    }
    private var showsWelcome: Bool {
        current.kind == "private" && model.selected?.id == thread.id && model.messages.isEmpty
            && current.status != "archived" && !openingHistory && !model.loadingHistory && model.errorMessage == nil
            && !editing && model.draft.isEmpty
            && !["queued", "running", "compacting"].contains(current.agentStatus ?? "")
    }

    private var timeline: some View {
        Group {
            if selectionMatches {
                if model.hasOlder, !model.messages.isEmpty {
                    Button(model.loadingHistory || pagingHistory ? "Loading earlier messages…" : "Load earlier messages") {
                        Task { await loadEarlier() }
                    }
                    .disabled(model.loadingHistory || pagingHistory).frame(minHeight: 44)
                    .accessibilityIdentifier("thread-earlier")
                }
                if current.kind == "private", !model.messages.isEmpty || showsWelcome {
                    #if os(iOS)
                        Label("Private · Only you and \(assistantName)", systemImage: "lock")
                            .font(.caption).foregroundStyle(.secondary).padding(.vertical, 12)
                    #endif
                    if showsWelcome { AtlasPipWelcome() }
                }
                AtlasThreadTimeline(timeline: model.timeline, selfId: selfId, openAttachment: openAttachment) { id, event in
                    await model.componentAction(messageId: id, event: event)
                }
                if current.kind == "private", !model.historyCached, let environmentRequest {
                    AtlasEnvironmentActivityView(threadId: thread.id, enabled: current.status != "archived",
                                                 request: environmentRequest)
                        .id(thread.id)
                }
                if let activity = model.activityMessage {
                    AtlasThreadActivity(message: activity,
                                        typing: model.selected?.agentStatus == "running" && model.activeToolName == nil)
                }
                if let error = model.errorMessage {
                    Text(error).font(.callout).foregroundStyle(.red)
                    Button("Retry") { Task { await model.history() } }.frame(minHeight: 44)
                }
            }
            Color.clear.frame(height: current.status == "archived" && !model.messages.isEmpty ? 49 : 1).id("thread-latest")
                .listRowInsets(EdgeInsets())
        }
    }

    private var scrollableTranscript: some View {
        AtlasThreadTranscript { timeline }
            .modifier(AtlasThreadScrollObserver(messageID: $visibleMessageID, anchor: scrollAnchor,
                                               following: scrolling.following,
                                               latest: selectionMatches ? model.messages.last : nil,
                                               activity: model.activityMessage, update: { metrics in
                guard selectionMatches else { return }
                if !jumpingToPrompt { scrolling.update(metrics) }
                if hasShownMessages, !scrolling.following, !jumpingToPrompt, metrics.offset < 240,
                   model.hasOlder, !model.loadingHistory, !pagingHistory, model.errorMessage == nil {
                    Task { await loadEarlier() }
                }
            }, interaction: { scrolling.userScrolling = $0 }))
            .scrollDismissesKeyboard(.interactively)
            .refreshable { if selectionMatches { await model.history() } }
            .onChange(of: model.messages.last?.id, initial: true) { _, latest in
                guard selectionMatches, latest != nil else { return }
                hasShownMessages = true
            }
            .overlay(alignment: .bottomTrailing) {
                if current.status == "archived" { threadNavigation.padding() }
            }
            .overlay {
                if !selectionMatches {
                    VStack(spacing: 12) {
                        if !openingHistory, let error = model.errorMessage {
                            Text(error).foregroundStyle(.red)
                            Button("Retry") { Task { await model.open(thread) } }
                                .disabled(model.loadingHistory)
                        } else {
                            ProgressView("Loading conversation…").accessibilityIdentifier("thread-history-loading")
                        }
                    }
                } else if (openingHistory || model.loadingHistory) && model.messages.isEmpty {
                    ProgressView("Loading conversation…").accessibilityIdentifier("thread-history-loading")
                }
            }
    }

    @ViewBuilder private var bottomBar: some View {
        if current.status == "archived" {
            HStack {
                Label("Archived conversation", systemImage: "archivebox").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if let selfId, current.ownerId == selfId {
                    Button { Task { await model.archive(current, archived: false) } } label: {
                        Text("Restore").frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(model.saving).accessibilityIdentifier("thread-restore")
                }
            }
            .padding(.horizontal).padding(.bottom, 8).background(.bar)
        } else if model.historyCached {
            Text("Saved conversation. Connect to refresh before sending.")
                .font(.footnote).foregroundStyle(.secondary)
                .padding().frame(maxWidth: .infinity).background(.bar)
                .accessibilityIdentifier("thread-saved-history")
        } else {
            composer
        }
    }

    @ViewBuilder private var conversation: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            scrollableTranscript.safeAreaBar(edge: .bottom, spacing: 0) {
                GlassEffectContainer(spacing: 0) { bottomBar }
            }
        } else {
            VStack(spacing: 0) {
                scrollableTranscript
                bottomBar
            }
        }
    }

    var body: some View {
        conversation
        .modifier(AtlasThemedContent())
        #if os(iOS)
        .navigationTitle(current.kind == "private" ? assistantName : current.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Tool environment", systemImage: "desktopcomputer") { showingEnvironment = true }
                    .disabled(model.historyCached || current.kind != "private" || current.status == "archived" || environmentRequest == nil)
                    .accessibilityIdentifier("thread-environment")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Thread details", systemImage: "info.circle") { showingInfo = true }
                    .accessibilityIdentifier("thread-info")
            }
        }
        .sheet(isPresented: $showingInfo) { AtlasThreadInfo(thread: current, assistantName: assistantName) }
        .sheet(isPresented: $showingEnvironment) {
            NavigationStack {
                if let environmentRequest { AtlasEnvironmentPicker(threadId: thread.id, request: environmentRequest) }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(uiColor: .systemGroupedBackground))
        }
        #endif
        .sheet(isPresented: $showingModels) {
            AtlasThreadModelPicker(model: model, threadId: thread.id)
                .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
            #if os(iOS)
                .presentationBackground(Color(uiColor: .systemGroupedBackground))
            #endif
        }
        .alert("Share this conversation?", isPresented: $confirmingShare) {
            Button("Cancel", role: .cancel) {}
            Button("Share and send") { send() }
        } message: {
            Text("Tagged people will be able to read the existing messages and attachments. " +
                "They will receive a ping and a conversation recap.")
        }
        .modifier(AtlasAttachmentPicker(photosPresented: $photosPresented, filesPresented: $filesPresented, upload: { file in
            guard !Task.isCancelled, model.selected?.id == thread.id else { return }
            await model.upload(filename: file.filename, contentType: file.contentType, data: file.data)
        }, failure: { attachmentError = $0 }))
        .modifier(AtlasAttachmentPreview(url: $previewURL))
        .alert("Attachment could not be opened", isPresented: Binding(get: { attachmentError != nil }, set: {
            if !$0 { attachmentError = nil }
        })) { Button("OK", role: .cancel) { attachmentError = nil } } message: { Text(attachmentError ?? "") }
        .task(id: thread.id) {
            resetPresentation()
            presence?.show()
            await model.open(thread)
            if !Task.isCancelled { openingHistory = false }
        }
        .onDisappear { startingVoice?.cancel(); openingAttachment?.cancel(); voice.cancel(); model.leave(id: thread.id) }
        .onChange(of: scenePhase) { _, phase in
            // Permission alerts temporarily deactivate the scene before their callbacks return.
            if phase == .background || (phase == .inactive && voice.phase != .requesting) {
                startingVoice?.cancel()
                voice.cancel()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: audioInterruption)) { _ in
            startingVoice?.cancel()
            voice.cancel()
        }
        .protectsAtlasNavigation(!model.draft.isEmpty || !model.draftAttachments.isEmpty || model.pendingUploadName != nil
            || model.saving || model.attachmentBusy || voice.busy)
    }
}

extension AtlasThreadDetail {
    private var threadNavigation: some View {
        Group {
            if selectionMatches {
                AtlasThreadNavigation(messages: model.messages, shared: current.kind != "private",
                                      hasOlder: model.hasOlder && !model.messages.isEmpty, loading: model.loadingHistory,
                                      showsLatest: !scrolling.following && !showsWelcome && !model.messages.isEmpty,
                                      older: { await loadEarlier() }, jump: { id in
                                          scrolling.following = id == "thread-latest"
                                          jumpingToPrompt = true
                                          withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                                              scrollAnchor = scrolling.following ? .bottom : .top
                                              visibleMessageID = id
                                          } completion: {
                                              guard selectionMatches else { return }
                                              scrolling.following = id == "thread-latest"
                                              jumpingToPrompt = false
                                          }
                                      })
                                      .id(thread.id)
            }
        }
    }

    private func resetPresentation() {
        startingVoice?.cancel()
        openingAttachment?.cancel()
        voice.cancel()
        scrolling.reset()
        visibleMessageID = nil
        scrollAnchor = .bottom
        jumpingToPrompt = false
        hasShownMessages = false
        openingHistory = true
        pagingHistory = false
        showingInfo = false
        showingEnvironment = false
        showingModels = false
        confirmingShare = false
        photosPresented = false
        filesPresented = false
        attachmentError = nil
        previewURL = nil
    }

    private var audioInterruption: Notification.Name {
        #if os(macOS)
            .AVAudioEngineConfigurationChange
        #else
            AVAudioSession.interruptionNotification
        #endif
    }

    private func loadEarlier() async {
        guard selectionMatches, !pagingHistory, !model.loadingHistory, model.hasOlder else { return }
        pagingHistory = true
        scrolling.following = false
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
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())
                        .accessibilityIdentifier("thread-presence")
                }
            }
            if let error = voice.errorMessage {
                Text(error).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("thread-voice-error")
            }
            AtlasDraftAttachments(model: model, open: openAttachment)
            HStack {
                AtlasThreadModelButton(model: model, thread: current,
                                       enabled: selectionMatches && current.ownerId == selfId && !model.saving && !voice.busy) {
                    showingModels = true
                }
                Spacer(minLength: 8)
                #if os(iOS)
                if editing {
                    Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") { editing = false }
                        .labelStyle(.iconOnly).buttonStyle(.plain).frame(width: 44, height: 44)
                        .modifier(AtlasComposerSurface(shape: Capsule(), interactive: true))
                        .accessibilityIdentifier("thread-hide-keyboard")
                }
                #endif
                threadNavigation
            }
            let suggestions = AtlasThreadSuggestion.prompts(messages: model.messages, welcome: showsWelcome,
                                                             agentStatus: current.agentStatus)
            if !suggestions.isEmpty, model.draft.isEmpty, model.draftAttachments.isEmpty,
               model.pendingUploadName == nil, !voice.busy, !model.saving {
                AtlasThreadSuggestions(suggestions: suggestions) {
                    model.draft = AtlasVoiceInput.appending($0, to: model.draft)
                }.id(suggestions.map(\.text))
            }
            AtlasThreadMentions(model: model, shared: current.kind != "private")
            AtlasThreadComposer(draft: Binding(get: { model.draft }, set: { model.draft = $0 }),
                                placeholder: current.kind == "private" ? "Message Pip" : "Message · @Pip to ask",
                                saving: model.saving || model.attachmentBusy || model.pendingUploadName != nil, phase: voice.phase,
                                levels: voice.levels, editing: $editing, hasAttachments: !model.draftAttachments.isEmpty,
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
                                    if current.kind == "private", !model.draftMentions.isEmpty { confirmingShare = true } else { send() }
                                })
                                .disabled(model.selected?.id != thread.id || openingHistory
                                    || (model.loadingHistory && model.messages.isEmpty))
        }
        .frame(maxWidth: 688).padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .opacity(selectionMatches ? 1 : 0)
    }
    private func send() {
        scrolling.following = true
        Task { await model.send() }
    }
}
