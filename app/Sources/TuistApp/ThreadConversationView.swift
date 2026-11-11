#if os(iOS)
    import SwiftUI
    import TuistServer
    import UIKit

    struct ThreadConversationDraft {
        var text = ""
        var people: Set<String> = []
    }

    struct ThreadConversationView: View {
        @State var thread: DemoThread
        let client: ThreadClient?
        var isLive: Bool { client != nil }
        @Binding var draft: ThreadConversationDraft
        @State var archived: Bool
        let update: (DemoThread) -> Void
        let archive: (Bool) -> Void
        @State var busy = false
        @State var error: String?
        @State var shipPreview: ThreadShipPreview?
        @State var loadingShipPreview = false
        @State var loadingHistory = false
        @State var historyID = UUID()
        @State var lifecycle = UUID()
        @State var requestID = UUID()
        @State var requestContent: String?
        @State var showingDetails = false
        @State var showingDiff = false
        @State var showingPrompts = false
        @State var confirmingShare = false
        @State var confirmingArchive = false
        @State var scrollID: String?
        @State var following = true
        @State var pendingJump: String?
        @FocusState var composing: Bool
        @StateObject var voice = ThreadVoiceInput()
        @Environment(\.scenePhase) private var scenePhase
        @Environment(\.accessibilityReduceMotion) var reduceMotion
        @Environment(\.dynamicTypeSize) var typeSize
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @Environment(\.colorSchemeContrast) private var contrast

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if thread.hasMore == true {
                        Button("Load earlier messages") { Task { await refresh(older: true) } }
                            .disabled(loadingHistory)
                    }
                    ForEach(timeline, id: \.first!.id) { group in
                        if group.first?.role == "tool" {
                            toolGroup(group)
                        } else if let message = group.first {
                            messageView(message)
                        }
                    }
                    if thread.isRunning {
                        HStack {
                            ProgressView()
                            Text("Tuist is working…").foregroundStyle(.secondary)
                        }
                    }
                    if thread.status == "outcome_unknown" {
                        Label(
                            "Tool outcome unknown. Nothing will be retried automatically.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                    }
                    if !thread.diff.isEmpty {
                        Button { showingDiff = true } label: {
                            Label("Review changes", systemImage: "doc.text.magnifyingglass")
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Capsule())
                                .modifier(ThreadGlassSurface(cornerRadius: 22, interactive: true))
                        }
                        .buttonStyle(.plain)
                    }
                    if let error {
                        Text(error).foregroundStyle(.red)
                        Button("Reconnect") { Task { await refresh() } }
                    }
                    Text(LocalizedStringKey(isLive ? "Private · Saved to your account" : "Design preview · Sample conversation"))
                        .font(.caption).foregroundStyle(.secondary)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .scrollTargetLayout()
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition(id: $scrollID, anchor: .bottom)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.top, for: .alignment)
            .safeAreaPadding(.horizontal, 20)
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height - geometry.visibleRect.maxY < 80
            } action: { _, atBottom in following = atBottom }
            .onChange(of: thread.messages) { _, _ in if following { jump(to: "bottom") } }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composer
            }
            .background {
                Color(uiColor: .systemBackground)
                    .overlay {
                        if !reduceTransparency, contrast != .increased {
                            LinearGradient(
                                colors: [.purple.opacity(0.08), .blue.opacity(0.025), .clear],
                                startPoint: .bottomTrailing, endPoint: .topLeading
                            )
                        }
                    }
                    .ignoresSafeArea()
            }
            .navigationTitle(thread.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(thread.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Label(thread.repository, systemImage: thread.visibility == "shared" ? "person.2" : "lock")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .modifier(ThreadGlassSurface(cornerRadius: 24))
                    .accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Thread details", systemImage: "info.circle") { showingDetails = true }
                        Button("Prompts", systemImage: "list.bullet") { showingPrompts = true }
                        Button("Latest message", systemImage: "arrow.down") { jump(to: "bottom") }
                        if !thread.diff.isEmpty {
                            Button("Review changes", systemImage: "doc.text.magnifyingglass") { showingDiff = true }
                        }
                        Button(archived ? "Restore thread" : "Archive thread", systemImage: "archivebox") {
                            if archived { setArchived(false) } else { confirmingArchive = true }
                        }
                    } label: { Image(systemName: "ellipsis") }
                        .accessibilityLabel("Conversation actions")
                }
            }
            .sheet(isPresented: $showingDetails) { details }
            .sheet(isPresented: $showingDiff, onDismiss: { shipPreview = nil }, content: { diffSheet })
            .sheet(isPresented: $showingPrompts, onDismiss: {
                if let pendingJump { jump(to: pendingJump); self.pendingJump = nil }
            }, content: { promptSheet })
            .alert("Share the conversation history?", isPresented: $confirmingShare) {
                Button("Cancel", role: .cancel) {}
                Button("Share preview and send") { Task { await send(shareConfirmed: true) } }
            } message: {
                Text(
                    "Inviting \(draft.people.sorted().joined(separator: ", ")) shares all existing messages, tool results, and future replies. This preview sends no invitations or notifications."
                )
            }
            .confirmationDialog("Archive this thread?", isPresented: $confirmingArchive, titleVisibility: .visible) {
                Button("Archive thread") { setArchived(true) }
            } message: {
                Text("Archiving cancels any active work. The conversation stays available in Archived.")
            }
            .onChange(of: draft.text) { _, text in
                let tokens = Set(text.split(whereSeparator: \.isWhitespace).map(String.init))
                draft.people = draft.people.filter { tokens.contains("@\($0)") }
            }
            .task(id: scenePhase) {
                guard let client, scenePhase == .active else { return }
                await refresh()
                await client.watch(threadID: thread.id, invalidate: { await refresh() }, disconnected: {
                    if error == nil { error = String(localized: "Connection lost. Reconnecting…") }
                })
            }
            .onDisappear { lifecycle = UUID(); historyID = UUID(); voice.cancel() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    lifecycle = UUID()
                    historyID = UUID()
                    shipPreview = nil
                    voice.cancel()
                }
            }
        }
    }

    struct ThreadGlassSurface: ViewModifier {
        let cornerRadius: CGFloat
        var interactive = false
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @Environment(\.colorSchemeContrast) private var contrast

        func body(content: Content) -> some View {
            content.background {
                let shape = RoundedRectangle(cornerRadius: cornerRadius)
                if reduceTransparency || contrast == .increased {
                    shape.fill(Color(uiColor: .secondarySystemBackground))
                        .overlay { shape.strokeBorder(.secondary.opacity(0.5), lineWidth: 1) }
                } else if #available(iOS 26.0, *) {
                    shape.fill(.clear).glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
                } else {
                    shape.fill(.regularMaterial)
                        .overlay { shape.strokeBorder(.secondary.opacity(0.2), lineWidth: 0.5) }
                }
            }
        }
    }
#endif
