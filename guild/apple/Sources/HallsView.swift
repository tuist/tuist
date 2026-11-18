import AVFoundation
import SwiftUI

struct HallPerson: Decodable, Hashable, Identifiable {
    let id: Int
    let handle: String?
    /// Has Tuist Guild open in this organization, decided by the core's presence.
    var online: Bool?
}

/// A green dot for someone who is online; nothing otherwise. The views that
/// show it also say "online" to VoiceOver, so the state never rests on color.
private struct OnlineDot: View {
    let online: Bool
    @ScaledMetric(relativeTo: .caption) private var size = 8.0

    var body: some View {
        if online {
            Circle().fill(Color.green)
                .frame(width: size, height: size)
                .overlay(Circle().stroke(Noora.backgroundPrimary, lineWidth: 1.5))
                .accessibilityHidden(true)
        }
    }
}

struct HallMessage: Decodable, Identifiable {
    let id: String
    let position: Int
    let body: String
    let author: HallPerson?
    let mine: Bool
    let inserted_at: String?

    var date: Date? { inserted_at.flatMap { ISO8601DateFormatter().date(from: $0) } }
}

/// A hall or direct conversation. `title` and `unread` are decided by the Rust core and server.
struct AppHall: Decodable, Identifiable {
    let id: String
    /// `hall` or `direct`.
    let kind: String
    let title: String
    let topic: String?
    let members: [HallPerson]
    let last_position: Int
    let unread: Int
    var last_message: HallMessage?
    var messages: [HallMessage]?
    var has_more: Bool?
    var next_before: Int?
}

private struct HallsPage: Decodable {
    let available: Bool
    /// `personal`, `disabled` or `sign_in_required`.
    let reason: String?
    let halls: [AppHall]
    let directs: [AppHall]
}

struct HallRoute: Hashable, Identifiable {
    let id: String
}

extension AppClient {
    func hall(_ operation: String, _ args: [String: Any]) async throws -> AppHall {
        let data = try await call(operation, args)
        return try JSONDecoder().decode(AppHall.self, from: JSONSerialization.data(withJSONObject: data))
    }
}

/// The Halls tab (the organization's halls) or the DMs tab (the person's
/// direct conversations): long-lived conversations between people, with no agent.
struct HallsView: View {
    let client: AppClient
    /// `halls` or `dms`, the tab this list is.
    let tab: String
    @State private var page: HallsPage?
    @State private var error: String?
    @State private var creating = false

    private var directs: Bool { tab == "dms" }
    private var title: LocalizedStringKey { directs ? "DMs" : "Halls" }
    private var createLabel: LocalizedStringKey { directs ? "New Message" : "New Hall" }
    private var rows: [AppHall] { directs ? page?.directs ?? [] : page?.halls ?? [] }

    var body: some View {
        List {
            if let error {
                Section {
                    Text(verbatim: error).foregroundStyle(.secondary)
                    Button("Try Again") { Task { await load() } }
                }
            }
            ForEach(rows) { hall in
                NavigationLink(value: HallRoute(id: hall.id)) { HallRow(hall: hall) }
                    .listRowBackground(Noora.backgroundTertiary)
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
        .background(Noora.backgroundPrimary)
        .overlay { if error == nil { emptyState } }
        .navigationTitle(title)
        .toolbar {
            if page?.available == true {
                ToolbarItem(placement: .primaryAction) {
                    Button(createLabel, systemImage: "square.and.pencil") { creating = true }
                        .help(createLabel)
                }
            }
        }
        .sheet(isPresented: $creating) {
            NavigationStack {
                if directs {
                    NewDirectView(client: client) { open($0) }
                } else {
                    NewHallView(client: client) { open($0) }
                }
            }
            #if os(iOS)
            .presentationDetents([.medium, .large])
            #endif
        }
        .refreshable { await load() }
        // ⌘N in the menu bar; both lists stay mounted, so only the open tab offers it.
        .focusedSceneValue(\.compose, page?.available == true && client.view.navigation.tab.rawValue == tab
            ? ComposeAction(title: createLabel) { creating = true } : nil)
        .task(id: client.view.generation) {
            // Another account or organization: never show the previous one's halls.
            page = nil
            // Halls change while nobody here is looking; keep unread counts current.
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(15))
            }
        }
        .onChange(of: client.view.navigation.revision) { _, _ in
            creating = false
            Task { await load() }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if let page {
            if !page.available {
                switch page.reason {
                case "personal":
                    ContentUnavailableView(
                        directs ? LocalizedStringKey("DMs Belong to Organizations") : "Halls Belong to Organizations",
                        systemImage: "person.3",
                        description: Text("Switch to an organization in the account menu to talk with its members.")
                    )
                case "sign_in_required":
                    ContentUnavailableView(
                        "Sign In Again to Use Halls",
                        systemImage: "person.badge.key",
                        description: Text("Your session is from an earlier version of Tuist Guild.")
                    )
                default:
                    ContentUnavailableView(
                        "Halls Aren't Available Yet",
                        systemImage: "number",
                        description: Text("Halls aren't enabled for this organization or server.")
                    )
                }
            } else if rows.isEmpty {
                ContentUnavailableView {
                    Label(directs ? LocalizedStringKey("No Messages Yet") : "No Halls Yet", systemImage: directs ? "bubble.left.and.text.bubble.right" : "number")
                } description: {
                    Text(directs
                        ? LocalizedStringKey("Message one or more people in your organization, without an agent.")
                        : "Halls are long-lived conversations everyone in your organization can join.")
                } actions: {
                    Button(createLabel) { creating = true }.prominentGlassButtonStyle()
                }
            }
        } else {
            ProgressView()
        }
    }

    private func open(_ hall: AppHall) {
        Task {
            await load()
            await client.perform("navigate", ["url": "/\(tab)/\(hall.id)"])
        }
    }

    private func load() async {
        let generation = client.view.generation
        do {
            let data = try await client.call("halls")
            let next = try JSONDecoder().decode(HallsPage.self, from: JSONSerialization.data(withJSONObject: data))
            // Selecting an organization keeps the profile but advances the generation.
            guard !Task.isCancelled, generation == client.view.generation else { return }
            page = next
            error = nil
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}

private struct HallRow: View {
    let hall: AppHall

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: hall.kind == "hall" ? "number" : hall.members.count > 1 ? "person.2" : "person")
                .foregroundStyle(hall.unread > 0 ? Noora.primary : Noora.labelSecondary)
                .frame(width: 20)
                .overlay(alignment: .bottomTrailing) {
                    OnlineDot(online: hall.kind == "direct" && hall.members.contains { $0.online == true })
                        .offset(x: 3, y: 3)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: hall.kind == "hall" ? String(hall.title.dropFirst()) : hall.title)
                    .font(Font.body.weight(hall.unread > 0 ? .semibold : .medium))
                    .foregroundStyle(Noora.labelPrimary)
                    .lineLimit(1)
                if let preview {
                    Text(verbatim: preview).font(.caption).foregroundStyle(Noora.labelSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if hall.unread > 0 {
                Text(verbatim: hall.unread > 99 ? "99+" : "\(hall.unread)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Noora.backgroundPrimary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Noora.primary, in: Capsule())
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
    }

    /// The row as VoiceOver reads it: who or where, presence, unread count, then the latest message.
    private var spoken: String {
        let online = hall.kind == "direct" && hall.members.contains { $0.online == true }
        return [
            hall.title,
            online ? String(localized: "Online") : nil,
            hall.unread > 0 ? String(localized: "\(hall.unread) unread") : nil,
            preview,
        ].compactMap { $0 }.joined(separator: ", ")
    }

    /// The latest message with its author, or the hall's topic when nobody has written yet.
    private var preview: String? {
        if let message = hall.last_message {
            let body = message.body.split(whereSeparator: \.isNewline).joined(separator: " ")
            if hall.kind == "direct", hall.members.count == 1 || message.mine {
                return message.mine ? String(localized: "You: \(body)") : body
            }
            return "\(message.author?.handle ?? String(localized: "Someone")): \(body)"
        }
        return hall.topic
    }
}

/// One hall or direct conversation, kept current while it is on screen.
struct HallConversationView: View {
    let client: AppClient
    let id: String
    @State private var hall: AppHall?
    @State private var older: [HallMessage] = []
    @State private var olderBefore: Int?
    @State private var loadingOlder = false
    @State private var reply = ""
    @State private var sending = false
    @State private var error: String?
    @State private var atLatest = true
    @State private var voice = VoiceInput()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var messages: [HallMessage] {
        let latest = hall?.messages ?? []
        let ids = Set(latest.map(\.id))
        return older.filter { !ids.contains($0.id) } + latest
    }

    private var hasOlder: Bool {
        olderBefore != nil || (older.isEmpty && hall?.has_more == true && hall?.next_before != nil)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if hasOlder {
                        Button(loadingOlder ? LocalizedStringKey("Loading Earlier Messages…") : LocalizedStringKey("Load Earlier Messages")) {
                            Task { await loadOlder() }
                        }
                        .disabled(loadingOlder)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    if let hall, messages.isEmpty, !hasOlder {
                        intro(hall)
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        HallMessageRow(message: message, continued: continues(index))
                            .id(message.id)
                    }
                    if let error {
                        Text(verbatim: error).font(.callout).foregroundStyle(Noora.labelDestructive)
                    }
                    Color.clear.frame(height: 1).id("latest")
                        .onAppear { atLatest = true }
                        .onDisappear { atLatest = false }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: hall?.messages?.last?.id) { _, _ in
                guard atLatest else { return }
                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("latest", anchor: .bottom) }
            }
        }
        .background(Noora.backgroundPrimary)
        .overlay { if hall == nil, error == nil { ProgressView() } }
        .safeAreaInset(edge: .bottom) {
            ReplyComposer(reply: $reply, disabled: hall == nil, sending: sending, voice: voice) {
                Task { await send() }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle(Text(verbatim: hall?.title ?? ""))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            // Only while someone can see it: a conversation left open behind
            // other apps must not mark new messages read.
            .task(id: FollowKey(id: id, active: scenePhase == .active)) {
                if scenePhase == .active { await follow() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background || (phase == .inactive && voice.phase != .requesting) { voice.cancel() }
            }
            .onDisappear { voice.cancel() }
    }

    private func intro(_ hall: AppHall) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: hall.title).font(.title2.weight(.semibold)).foregroundStyle(Noora.labelPrimary)
            Group {
                if let topic = hall.topic, hall.kind == "hall" {
                    Text(verbatim: topic)
                } else if hall.kind == "hall" {
                    Text("This is the start of the hall. Everyone in your organization can read it.")
                } else {
                    Text("This is the start of your conversation. Only the people in it can read it.")
                }
            }
            .foregroundStyle(Noora.labelSecondary)
        }
        .padding(.bottom, 12)
    }

    /// Consecutive messages from the same person within five minutes share one header.
    private func continues(_ index: Int) -> Bool {
        guard index > 0 else { return false }
        let (previous, message) = (messages[index - 1], messages[index])
        guard previous.author?.id == message.author?.id, let a = previous.date, let b = message.date else { return false }
        return b.timeIntervalSince(a) < 300
    }

    /// Polls while the conversation is on screen; people write at any time.
    private func follow() async {
        while !Task.isCancelled {
            do {
                show(try await client.hall("hall", ["id": id]))
                error = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    /// Shows a newer latest page and marks it read.
    private func show(_ latest: AppHall) {
        if !older.isEmpty, let previous = hall?.messages {
            let kept = Set((latest.messages ?? []).map(\.id)).union(older.map(\.id))
            older += previous.filter { !kept.contains($0.id) }
        }
        hall = latest
        if latest.unread > 0 {
            Task { _ = try? await client.call("read_hall", ["id": id, "position": latest.last_position]) }
        }
    }

    private func loadOlder() async {
        guard !loadingOlder, let before = olderBefore ?? (older.isEmpty ? hall?.next_before : nil) else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let page = try await client.hall("hall", ["id": id, "before": before])
            let known = Set(messages.map(\.id))
            older = (page.messages ?? []).filter { !known.contains($0.id) } + older
            olderBefore = page.has_more == true ? page.next_before : nil
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func send() async {
        let text = reply
        guard !sending, !voice.busy, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            show(try await client.hall("send_hall_message", ["id": id, "content": text]))
            reply = ""
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct FollowKey: Equatable {
    let id: String
    let active: Bool
}

private struct HallMessageRow: View {
    let message: HallMessage
    let continued: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if continued {
                Color.clear.frame(width: 32, height: 1)
            } else {
                Text(verbatim: String((message.author?.handle ?? "?").prefix(1)).uppercased())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(message.mine ? Noora.backgroundPrimary : Noora.labelPrimary)
                    .frame(width: 32, height: 32)
                    .background(message.mine ? Noora.primary : Noora.neutralHover, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .bottomTrailing) {
                        OnlineDot(online: online).offset(x: 2, y: 2)
                    }
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                if !continued {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: author)
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Noora.labelPrimary)
                            .accessibilityLabel(online ? Text("\(author), online") : Text(verbatim: author))
                        if let date = message.date {
                            Text(date, format: .dateTime.hour().minute())
                                .font(.caption).foregroundStyle(Noora.labelSecondary)
                        }
                    }
                }
                Text(markdown(message.body)).textSelection(.enabled).foregroundStyle(Noora.labelPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, continued ? 0 : 8)
        .accessibilityElement(children: .combine)
    }

    private var author: String { message.author?.handle ?? String(localized: "Someone") }
    private var online: Bool { !message.mine && message.author?.online == true }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// Names a new hall, and optionally what it is for.
private struct NewHallView: View {
    let client: AppClient
    let created: (AppHall) -> Void
    @State private var name = ""
    @State private var topic = ""
    @State private var creating = false
    @State private var error: String?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name, prompt: Text(verbatim: "releases"))
                    .focused($focused)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    // Return confirms, like the sheet's Create button.
                    .onSubmit { if canCreate { Task { await create() } } }
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                TextField("Topic (optional)", text: $topic, axis: .vertical).lineLimit(1 ... 3)
            } footer: {
                Text("Everyone in your organization can read and write in it.")
            }
            if let error {
                Text(verbatim: error).foregroundStyle(Noora.labelDestructive)
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .frame(width: 440, height: 280)
        #endif
        .disabled(creating)
        .navigationTitle("New Hall")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(!canCreate)
                }
            }
            .onAppear { focused = true }
    }

    private var canCreate: Bool { !creating && !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private func create() async {
        creating = true
        defer { creating = false }
        do {
            let hall = try await client.hall("create_hall", ["name": name, "topic": topic])
            dismiss()
            created(hall)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Picks people in the organization to message directly.
private struct NewDirectView: View {
    let client: AppClient
    let created: (AppHall) -> Void
    @State private var people: [HallPerson]?
    @State private var chosen: Set<Int> = []
    @State private var search = ""
    @State private var starting = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var matches: [HallPerson] {
        let all = people ?? []
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return query.isEmpty ? all : all.filter { ($0.handle ?? "").lowercased().contains(query) }
    }

    var body: some View {
        List {
            if let error {
                Text(verbatim: error).foregroundStyle(Noora.labelDestructive)
            }
            Section {
                ForEach(matches) { person in
                    let selected = chosen.contains(person.id)
                    Button {
                        if selected { chosen.remove(person.id) } else { chosen.insert(person.id) }
                    } label: {
                        HStack {
                            Text(verbatim: person.handle ?? "").foregroundStyle(Noora.labelPrimary)
                            OnlineDot(online: person.online == true)
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark").foregroundStyle(Noora.primary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // A full conversation dims everyone else instead of ignoring taps.
                    .disabled(!selected && chosen.count >= Self.limit)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityValue(person.online == true ? Text("Online") : Text(verbatim: ""))
                }
            } footer: {
                if people?.isEmpty == false {
                    Text("You can message up to \(Self.limit) people at once.")
                }
            }
        }
        .overlay {
            if people == nil, error == nil { ProgressView() }
            else if people?.isEmpty == true {
                ContentUnavailableView("Nobody Else Is Here Yet", systemImage: "person.3",
                                       description: Text("Invite people to your organization to message them."))
            }
        }
        .searchable(text: $search, prompt: Text("Find people"))
        #if os(macOS)
            .frame(width: 400, height: 460)
        #endif
            .navigationTitle("New Message")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Message") { Task { await start() } }.disabled(starting || chosen.isEmpty)
                }
            }
            .task {
                do {
                    let data = try await client.call("hall_people")
                    people = try JSONDecoder().decode([HallPerson].self, from: JSONSerialization.data(withJSONObject: data["people"] ?? [Any]()))
                } catch {
                    self.error = error.localizedDescription
                }
            }
    }

    /// The server allows eight people in a conversation, you included.
    private static let limit = 7

    private func start() async {
        starting = true
        defer { starting = false }
        do {
            let hall = try await client.hall("start_direct", ["user_ids": chosen.sorted()])
            dismiss()
            created(hall)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
