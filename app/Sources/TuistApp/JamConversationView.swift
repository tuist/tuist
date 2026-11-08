#if os(iOS)
    import SwiftUI
    import TuistServer
    import UIKit

    struct JamConversationDraft {
        var text = ""
        var people: Set<String> = []
    }

    struct JamConversationView: View {
        @State var jam: DemoJam
        let client: JamClient?
        var isLive: Bool { client != nil }
        @Binding var draft: JamConversationDraft
        @State var archived: Bool
        let update: (DemoJam) -> Void
        let archive: (Bool) -> Void
        @State var busy = false
        @State var error: String?
        @State var shipPreview: JamShipPreview?
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
        @Environment(\.scenePhase) private var scenePhase
        @Environment(\.accessibilityReduceMotion) var reduceMotion
        @Environment(\.dynamicTypeSize) var typeSize
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @Environment(\.colorSchemeContrast) private var contrast

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if jam.hasMore == true {
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
                    if jam.isRunning {
                        HStack {
                            ProgressView()
                            Text("Tuist is working…").foregroundStyle(.secondary)
                        }
                    }
                    if jam.status == "outcome_unknown" {
                        Label(
                            "Tool outcome unknown. Nothing will be retried automatically.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                    }
                    if !jam.diff.isEmpty {
                        Button { showingDiff = true } label: {
                            Label("Review changes", systemImage: "doc.text.magnifyingglass")
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Capsule())
                                .modifier(JamGlassSurface(cornerRadius: 22, interactive: true))
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
            .onChange(of: jam.messages) { _, _ in if following { jump(to: "bottom") } }
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
            .navigationTitle(jam.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(jam.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Label(jam.repository, systemImage: jam.visibility == "shared" ? "person.2" : "lock")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .modifier(JamGlassSurface(cornerRadius: 24))
                    .accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Jam details", systemImage: "info.circle") { showingDetails = true }
                        Button("Prompts", systemImage: "list.bullet") { showingPrompts = true }
                        Button("Latest message", systemImage: "arrow.down") { jump(to: "bottom") }
                        if !jam.diff.isEmpty {
                            Button("Review changes", systemImage: "doc.text.magnifyingglass") { showingDiff = true }
                        }
                        Button(archived ? "Restore jam" : "Archive jam", systemImage: "archivebox") {
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
            .confirmationDialog("Archive this jam?", isPresented: $confirmingArchive, titleVisibility: .visible) {
                Button("Archive jam") { setArchived(true) }
            } message: {
                Text("The conversation stays available in Archived.")
            }
            .onChange(of: draft.text) { _, text in
                let tokens = Set(text.split(whereSeparator: \.isWhitespace).map(String.init))
                draft.people = draft.people.filter { tokens.contains("@\($0)") }
            }
            .task(id: scenePhase) {
                guard let client, scenePhase == .active else { return }
                await refresh()
                await client.watch(jamID: jam.id, invalidate: { await refresh() }, disconnected: {
                    if error == nil { error = String(localized: "Connection lost. Reconnecting…") }
                })
            }
            .onDisappear { lifecycle = UUID(); historyID = UUID() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { lifecycle = UUID(); historyID = UUID(); shipPreview = nil }
            }
        }
    }

    struct JamGlassSurface: ViewModifier {
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
