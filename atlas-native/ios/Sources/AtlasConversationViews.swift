import Combine
import SwiftUI

struct AtlasConversationsView: View {
    @StateObject private var model: AtlasConversations
    @State private var path: [AtlasConversation] = []
    @State private var creating = false
    @State private var selfId: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.atlasPresence) private var presence

    init(request: @escaping ([String: Any]) async throws -> Data,
         localRequest: @escaping ([String: Any]) async throws -> Data) {
        _model = StateObject(wrappedValue: AtlasConversations(request: request, localRequest: localRequest))
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let bot = model.bot {
                    Section {
                        Button {
                            Task { if let conversation = await model.privateConversation() { path.append(conversation) } }
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(bot.name).font(.headline)
                                    Text("Your private conversation").font(.subheadline).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: "sparkles") }
                            .frame(minHeight: 44)
                        }
                        .disabled(model.creating)
                        .accessibilityIdentifier("conversations-private")
                        if !bot.configured {
                            Label {
                                Text("An administrator needs to configure the Conversations inference profile before the agent can reply.")
                            } icon: { Image(systemName: "info.circle") }
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Shared conversations") {
                    let shared = model.conversations.filter { $0.kind != "private" }
                    ForEach(shared) { conversation in
                        NavigationLink(value: conversation) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(conversation.title).font(.headline)
                                if !conversation.summary.isEmpty {
                                    Text(conversation.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Text(conversation.status.capitalized).font(.caption).foregroundStyle(.secondary)
                            }.frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("conversation-\(conversation.id)")
                    }
                    if shared.isEmpty, !model.loading, model.bot != nil {
                        ContentUnavailableView("Work starts with a conversation", systemImage: "bubble.left.and.bubble.right",
                                               description: Text("Start one with your team. Connected monitors can also open conversations "
                                                + "when something needs attention."))
                    }
                    if model.hasMore {
                        Button("Load more") { Task { await model.load(more: true) } }.disabled(model.loading)
                    }
                }
                if model.loading { ProgressView("Loading conversations") }
                if let error = model.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red)
                        Button("Retry") { Task { await model.load() } }.disabled(model.loading)
                    }
                }
            }
            .modifier(AtlasThemedContent())
            .navigationTitle("Conversations")
            .navigationDestination(for: AtlasConversation.self) { conversation in
                AtlasConversationDetail(model: model, conversation: conversation, selfId: selfId)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New conversation", systemImage: "square.and.pencil") { creating = true }
                        .disabled(model.bot == nil).accessibilityIdentifier("conversations-create")
                }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
            .onAppear { presence?.show() }
            .sheet(isPresented: $creating) {
                AtlasCreateConversation(model: model, people: presence?.people ?? []) { conversation in
                    creating = false
                    path.append(conversation)
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

private struct AtlasConversationDetail: View {
    @ObservedObject var model: AtlasConversations
    let conversation: AtlasConversation
    let selfId: String?
    @State private var addressAgent = false
    @State private var followLatest = true
    @State private var hasShownMessages = false
    @State private var showingInfo = false
    @Environment(\.atlasPresence) private var presence

    private var botName: String { model.bot?.name ?? "the agent" }
    private var current: AtlasConversation { model.selected ?? conversation }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if model.hasOlder {
                            Button("Load earlier messages") { followLatest = false; Task { await model.history(older: true) } }
                                .disabled(model.loadingHistory).frame(minHeight: 44)
                        }
                        if conversation.kind == "private" {
                            Label("Private · Only you and \(botName)", systemImage: "lock")
                                .font(.caption).foregroundStyle(.secondary).padding(.vertical, 12)
                        }
                        ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                            if startsDay(at: index), let date = ISO8601DateFormatter().date(from: message.insertedAt) {
                                Text(date, format: .dateTime.month(.abbreviated).day().year())
                                    .font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.vertical, 8)
                            }
                            AtlasConversationMessageView(message: message, selfId: selfId) { event in
                                await model.componentAction(messageId: message.id, event: event)
                            }
                            .id(message.id)
                        }
                        if model.loadingHistory { ProgressView("Loading history") }
                        if let error = model.errorMessage {
                            Text(error).font(.callout).foregroundStyle(.red)
                            Button("Retry") { Task { await model.history() } }.frame(minHeight: 44)
                        }
                        Color.clear.frame(height: 1).id("conversation-latest")
                            .background {
                                GeometryReader { position in
                                    Color.clear.preference(key: AtlasConversationBottom.self,
                                                           value: position.frame(in: .named("conversation-history")).maxY)
                                }
                            }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .bottom)
                }
                .coordinateSpace(name: "conversation-history")
                .onPreferenceChange(AtlasConversationBottom.self) { bottom in
                    followLatest = bottom.isFinite && bottom >= 0 && bottom <= geometry.size.height + 20
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .modifier(AtlasThemedContent())
                .refreshable { await model.history() }
                .onChange(of: model.messages.last?.id) { _, latest in
                    guard latest != nil else { return }
                    if !hasShownMessages || followLatest { scroll.scrollTo("conversation-latest", anchor: .bottom) }
                    hasShownMessages = true
                }
                .overlay(alignment: .bottomTrailing) {
                    if !followLatest {
                        Button("Latest messages", systemImage: "arrow.down") {
                            followLatest = true
                            scroll.scrollTo("conversation-latest", anchor: .bottom)
                        }
                        .labelStyle(.iconOnly).buttonStyle(.borderedProminent)
                        .frame(minWidth: 44, minHeight: 44).padding()
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .navigationTitle(conversation.kind == "private" ? botName : conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Conversation details", systemImage: "info.circle") { showingInfo = true }
                    .accessibilityIdentifier("conversation-info")
            }
        }
        .sheet(isPresented: $showingInfo) { details }
        .task(id: conversation.id) { presence?.show(); await model.open(conversation) }
        .onDisappear { model.leave(id: conversation.id) }
        .protectsAtlasNavigation(!model.draft.isEmpty || model.saving)
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
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("conversation-presence")
                }
            }
            if conversation.kind != "private" {
                Button { addressAgent.toggle() } label: {
                    Label("Ask \(botName)", systemImage: addressAgent ? "checkmark.circle.fill" : "sparkles")
                        .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityValue(addressAgent ? "On" : "Off")
                .accessibilityIdentifier("conversation-address-agent")
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(conversation.kind == "private" ? "Message \(botName)" : "Message the team",
                          text: Binding(get: { model.draft }, set: { model.draft = $0 }), axis: .vertical)
                    .lineLimit(1...6).textFieldStyle(.plain).padding(.leading, 12).padding(.vertical, 12)
                    .accessibilityIdentifier("conversation-composer")
                Button {
                    followLatest = true
                    Task { await model.send(addressAgent: addressAgent) }
                } label: {
                    Group {
                        if model.saving { ProgressView() } else { Image(systemName: "arrow.up").font(.headline.bold()) }
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.circle)
                .modifier(AtlasPrimaryAction()).accessibilityLabel("Send message")
                .disabled(model.saving || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("conversation-send")
            }
            .padding(6).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 28))
        }
        .frame(maxWidth: 688).padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
        .frame(maxWidth: .infinity).background(.bar)
    }

    private var details: some View {
        NavigationStack {
            Form {
                Section("Conversation") {
                    if current.kind == "private" { Label("Only you and \(botName)", systemImage: "lock") }
                    if !current.summary.isEmpty { Text(current.summary) }
                    if !current.origin.isEmpty { LabeledContent("Started from", value: current.origin.capitalized) }
                    LabeledContent("Status", value: current.status.capitalized)
                }
                if current.kind != "private" {
                    Section("Participants") { ForEach(current.participants) { Text($0.name) } }
                }
            }
            .navigationTitle("Conversation details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingInfo = false } } }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct AtlasConversationMessageView: View {
    let message: AtlasConversationMessage
    let selfId: String?
    let action: (String) async -> Bool
    @State private var showingEvidence = false
    @Environment(\.atlasTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var outgoing: Bool { message.kind == "human" && selfId != nil && message.authorId == selfId }
    private var palette: AtlasTheme.Palette? { contrast == .increased ? nil : theme?.palette(scheme) }
    private var fill: Color {
        if outgoing { return palette.map { Color(atlasHex: $0.accent) } ?? AtlasSettingsStyle.tint }
        return palette.map { Color(atlasHex: $0.surface) } ?? Color(uiColor: .secondarySystemGroupedBackground)
    }

    var body: some View {
        Group {
            if message.kind == "system" {
                Text(message.body).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            } else {
                HStack(alignment: .bottom, spacing: 0) {
                    if outgoing { Spacer(minLength: 40) }
                    VStack(alignment: outgoing ? .trailing : .leading, spacing: 5) {
                        if !outgoing, message.kind != "tool" {
                            Text(message.authorName).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                        }
                        if message.kind == "tool" {
                            tool.padding(14).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 18))
                        } else {
                            Text(message.body).textSelection(.enabled).padding(.horizontal, 16).padding(.vertical, 12)
                                .foregroundStyle(outgoing
                                    ? palette.map { Color(atlasHex: $0.onAccent) } ?? AtlasSettingsStyle.onTint : .primary)
                                .background(fill, in: RoundedRectangle(cornerRadius: 20))
                        }
                        if let date = ISO8601DateFormatter().date(from: message.insertedAt) {
                            Text(date, style: .time).font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 12)
                        }
                    }
                    if !outgoing { Spacer(minLength: 40) }
                }
            }
        }
        .accessibilityIdentifier("conversation-message-\(message.id)")
    }

    private var tool: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                if let card = message.component {
                    AtlasConversationCardView(card: card) { event in
                        Task { if await action(event) { showingEvidence = true } }
                    }
                }
                if message.component == nil || showingEvidence {
                    if !message.toolInput.isEmpty {
                        Text("Inputs").font(.caption.bold())
                        Text(message.toolInput).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    if !message.toolOutput.isEmpty {
                        Text("Result").font(.caption.bold())
                        Text(message.toolOutput).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                if !message.body.isEmpty { Text(message.body).font(.callout).textSelection(.enabled) }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
        } label: {
            Label("\(message.toolName ?? "Tool") · \(message.toolStatus ?? "Working")", systemImage: "wrench.and.screwdriver")
                .font(.subheadline)
        }
        .multilineTextAlignment(.leading)
    }
}

private struct AtlasConversationBottom: PreferenceKey {
    static var defaultValue: CGFloat { .infinity }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct AtlasCreateConversation: View {
    @ObservedObject var model: AtlasConversations
    let people: [AtlasPerson]
    let created: (AtlasConversation) -> Void
    @State private var title = ""
    @State private var participants: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Purpose") { TextField("Conversation title", text: $title).disabled(model.creating) }
                Section {
                    ForEach(people) { person in
                        Toggle(person.name, isOn: Binding(get: { participants.contains(person.id) }, set: { value in
                            if value { participants.insert(person.id) } else { participants.remove(person.id) }
                        })).disabled(model.creating)
                    }
                } header: { Text("Participants") } footer: {
                    Text("Only participants can read this conversation. The server checks access before tools are used.")
                }
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("New conversation").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.creating) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            if let conversation = await model.create(title: title, participants: Array(participants)) {
                                created(conversation)
                            }
                        }
                    }.disabled(model.creating || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(model.creating)
            .protectsAtlasNavigation(model.creating || !title.isEmpty)
        }
    }
}
