import SwiftUI

struct AtlasConversationsView: View {
    @StateObject private var model: AtlasConversations
    @State private var path: [AtlasConversation] = []
    @State private var creating = false
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
                AtlasConversationDetail(model: model, conversation: conversation)
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
        .onAppear { model.setActive(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in model.setActive(phase == .active) }
        .onDisappear { model.setActive(false) }
    }
}

private struct AtlasConversationDetail: View {
    @ObservedObject var model: AtlasConversations
    let conversation: AtlasConversation
    @State private var addressAgent = false
    @State private var followLatest = true
    @Environment(\.atlasPresence) private var presence

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if let selected = model.selected {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(selected.kind == "private"
                                ? "Private · Only you and \(model.bot?.name ?? "the agent")"
                                : selected.participants.map(\.name).joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                            if !selected.origin.isEmpty {
                                Text("Started from \(selected.origin)").font(.caption).foregroundStyle(.secondary)
                            }
                            if !selected.summary.isEmpty { Text(selected.summary).font(.subheadline) }
                            Label(selected.status.capitalized, systemImage: "circle.dotted").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if model.hasOlder {
                        Button("Load earlier messages") { followLatest = false; Task { await model.history(older: true) } }
                            .disabled(model.loadingHistory).frame(minHeight: 44)
                    }
                    ForEach(model.messages) { message in
                        AtlasConversationMessageView(message: message)
                            .id(message.id)
                    }
                    if model.loadingHistory { ProgressView("Loading history") }
                    if let error = model.errorMessage {
                        Text(error).foregroundStyle(.red)
                        Button("Retry") { Task { await model.history() } }.frame(minHeight: 44)
                    }
                    Color.clear.frame(height: 1).id("conversation-latest")
                        .onAppear { followLatest = true }
                        .onDisappear { followLatest = false }
                }
                .padding()
            }
            .refreshable { await model.history() }
            .onChange(of: model.messages.last?.id) { _, _ in
                if followLatest { scroll.scrollTo("conversation-latest", anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Latest messages", systemImage: "arrow.down.to.line") {
                        followLatest = true
                        scroll.scrollTo("conversation-latest", anchor: .bottom)
                    }
                }
            }
        }
        .navigationTitle(conversation.kind == "private" ? model.bot?.name ?? conversation.title : conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: conversation.id) { presence?.show(); await model.open(conversation) }
        .onDisappear { model.leave(id: conversation.id) }
        .protectsAtlasNavigation(!model.draft.isEmpty || model.saving)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = model.liveMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            } else if !model.viewers.isEmpty {
                Text(model.viewers.map { $0.name + ($0.typing ? " is typing…" : " is here") }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("conversation-presence")
            }
            if conversation.kind != "private" {
                Toggle("Ask \(model.bot?.name ?? "the agent")", isOn: $addressAgent).font(.subheadline)
            }
            HStack(alignment: .bottom) {
                TextField("Message", text: Binding(get: { model.draft }, set: { model.draft = $0 }), axis: .vertical)
                    .lineLimit(1...6).textFieldStyle(.roundedBorder).accessibilityIdentifier("conversation-composer")
                Button {
                    followLatest = true
                    Task { await model.send(addressAgent: addressAgent) }
                } label: {
                    if model.saving { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title) }
                }
                .frame(minWidth: 44, minHeight: 44).accessibilityLabel("Send message")
                .disabled(model.saving || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("conversation-send")
            }
        }
        .padding(.horizontal).padding(.vertical, 10).background(.bar)
    }
}

private struct AtlasConversationMessageView: View {
    let message: AtlasConversationMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(message.authorName).font(.subheadline.bold())
                Spacer()
                if let date = ISO8601DateFormatter().date(from: message.insertedAt) {
                    Text(date, style: .time).font(.caption).foregroundStyle(.secondary)
                }
            }
            if message.kind == "tool" {
                DisclosureGroup {
                    if !message.toolInput.isEmpty {
                        Text("Inputs").font(.caption.bold())
                        Text(message.toolInput).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    if !message.toolOutput.isEmpty {
                        Text("Result").font(.caption.bold())
                        Text(message.toolOutput).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    if !message.body.isEmpty { Text(message.body).textSelection(.enabled) }
                } label: {
                    Label("\(message.toolName ?? "Tool") · \(message.toolStatus ?? "Working")", systemImage: "wrench.and.screwdriver")
                        .font(.subheadline)
                }
            } else {
                Text(message.body).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("conversation-message-\(message.id)")
    }
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
