import AVFoundation
import SwiftUI

struct LoungePerson: Decodable, Hashable, Identifiable {
    let id: Int
    let handle: String?
    /// Has Luft open in this organization, decided by the core's presence.
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

struct LoungeMessage: Decodable, Identifiable {
    let id: String
    let position: Int
    let body: String
    let author: LoungePerson?
    let mine: Bool
    let inserted_at: String?

    var date: Date? { inserted_at.flatMap { ISO8601DateFormatter().date(from: $0) } }
}

/// A lounge or direct conversation. `title` and `unread` are decided by the Rust core and server.
struct AppLounge: Decodable, Identifiable {
    let id: String
    /// `lounge` or `direct`.
    let kind: String
    let title: String
    let topic: String?
    let members: [LoungePerson]
    let last_position: Int
    let unread: Int
    var last_message: LoungeMessage?
    var messages: [LoungeMessage]?
    var has_more: Bool?
    var next_before: Int?
    /// Everyone in a lounge: who opened, wrote in or was invited to it.
    var member_ids: [Int]?
}

struct LoungesPage: Decodable {
    let available: Bool
    /// `personal`, `disabled` or `sign_in_required`.
    let reason: String?
    let lounges: [AppLounge]
    let directs: [AppLounge]
}

extension AppClient {
    func lounge(_ operation: String, _ args: [String: Any]) async throws -> AppLounge {
        let data = try await call(operation, args)
        return try JSONDecoder().decode(AppLounge.self, from: JSONSerialization.data(withJSONObject: data))
    }
}

/// The Lounges tab (the organization's lounges) or the DMs tab (the person's
/// direct conversations): long-lived conversations between people, with no agent.
struct LoungesView: View {
    let client: AppClient
    /// `lounges` or `dms`, the tab this list is.
    let tab: String
    /// Lounges and DMs from one `lounges` answer, owned by `AppWorkspace` so switching
    /// tabs shows them as they were instead of a spinner.
    let inbox: LoungeInbox
    /// The Mac's open conversation: the list is the middle column of a split view, as in Mail.
    var selection: Binding<String?> = .constant(nil)
    @State private var creating = false

    private var page: LoungesPage? { inbox.page }
    private var error: String? { inbox.error }

    private var directs: Bool { tab == "dms" }
    private var title: LocalizedStringKey { directs ? "DMs" : "Lounges" }
    private var createLabel: LocalizedStringKey { directs ? "New Message" : "New Lounge" }
    private var rows: [AppLounge] { directs ? page?.directs ?? [] : page?.lounges ?? [] }

    var body: some View {
        list
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
                    NewLoungeView(client: client) { open($0) }
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
        // Another account or organization advances the generation, which gives the workspace a new inbox.
        .task(id: client.view.generation) {
            // Lounges change while nobody here is looking; keep unread counts current.
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
                        directs ? LocalizedStringKey("DMs Belong to Organizations") : "Lounges Belong to Organizations",
                        systemImage: "person.3",
                        description: Text("Switch to an organization in the account menu to talk with its members.")
                    )
                case "sign_in_required":
                    ContentUnavailableView(
                        "Sign In Again to Use Lounges",
                        systemImage: "person.badge.key",
                        description: Text("Your session is from an earlier version of Luft.")
                    )
                default:
                    ContentUnavailableView(
                        "Lounges Aren't Available Yet",
                        systemImage: "number",
                        description: Text("Lounges aren't enabled for this organization or server.")
                    )
                }
            } else if rows.isEmpty {
                ContentUnavailableView {
                    Label(directs ? LocalizedStringKey("No Messages Yet") : "No Lounges Yet", systemImage: directs ? "bubble.left.and.text.bubble.right" : "number")
                } description: {
                    Text(directs
                        ? LocalizedStringKey("Message one or more people in your organization, without an agent.")
                        : "Lounges are long-lived conversations everyone in your organization can join.")
                } actions: {
                    Button(createLabel) { creating = true }.prominentGlassButtonStyle()
                }
            }
        } else {
            ProgressView()
        }
    }

    private var list: some View {
        #if os(macOS)
            // Conversations, as in Messages: no row fills or rules, only the system's selection.
            List(selection: selection) {
                errorSection
                ForEach(rows) { lounge in
                    LoungeRow(lounge: lounge).tag(lounge.id).listRowSeparator(.hidden)
                }
            }
        #else
            List {
                errorSection
                ForEach(rows) { lounge in
                    NavigationLink(value: WorkspaceRoute.lounge(lounge.id)) { LoungeRow(lounge: lounge) }
                        .listRowBackground(Noora.backgroundTertiary)
                }
            }
        #endif
    }

    @ViewBuilder private var errorSection: some View {
        if let error {
            Section {
                Text(verbatim: error).foregroundStyle(.secondary)
                Button("Try Again") { Task { await load() } }
            }
        }
    }

    private func open(_ lounge: AppLounge) {
        Task {
            await load()
            await client.perform("navigate", ["url": "/\(tab)/\(lounge.id)"])
        }
    }

    private func load() async { await inbox.load(client) }
}

/// The selected organization's lounges and DMs, for both `LoungesView`s. One per signed-in generation.
@MainActor @Observable
final class LoungeInbox {
    private(set) var page: LoungesPage?
    private(set) var error: String?

    func load(_ client: AppClient) async {
        let generation = client.view.generation
        do {
            let data = try await client.call("lounges")
            let next = try JSONDecoder().decode(LoungesPage.self, from: JSONSerialization.data(withJSONObject: data))
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

private struct LoungeRow: View {
    let lounge: AppLounge

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: lounge.kind == "lounge" ? "number" : lounge.members.count > 1 ? "person.2" : "person")
                .foregroundStyle(lounge.unread > 0 ? Noora.primary : Noora.labelSecondary)
                .frame(width: 20)
                .overlay(alignment: .bottomTrailing) {
                    OnlineDot(online: lounge.kind == "direct" && lounge.members.contains { $0.online == true })
                        .offset(x: 3, y: 3)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: lounge.kind == "lounge" ? String(lounge.title.dropFirst()) : lounge.title)
                    .font(Font.body.weight(lounge.unread > 0 ? .semibold : .medium))
                    .foregroundStyle(Noora.labelPrimary)
                    .lineLimit(1)
                if let preview {
                    Text(verbatim: preview).font(.caption).foregroundStyle(Noora.labelSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if lounge.unread > 0 {
                Text(verbatim: lounge.unread > 99 ? "99+" : "\(lounge.unread)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Noora.backgroundPrimary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Noora.primary, in: Capsule())
            }
        }
        // The Mac's rows breathe like Messages'; the iPhone's stay compact.
        #if os(macOS)
        .padding(.vertical, 6)
        #else
        .padding(.vertical, 2)
        #endif
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
    }

    /// The row as VoiceOver reads it: who or where, presence, unread count, then the latest message.
    private var spoken: String {
        let online = lounge.kind == "direct" && lounge.members.contains { $0.online == true }
        return [
            lounge.title,
            online ? String(localized: "Online") : nil,
            lounge.unread > 0 ? String(localized: "\(lounge.unread) unread") : nil,
            preview,
        ].compactMap { $0 }.joined(separator: ", ")
    }

    /// The latest message with its author, or the lounge's topic when nobody has written yet.
    private var preview: String? {
        if let message = lounge.last_message {
            let body = message.body.split(whereSeparator: \.isNewline).joined(separator: " ")
            if lounge.kind == "direct", lounge.members.count == 1 || message.mine {
                return message.mine ? String(localized: "You: \(body)") : body
            }
            return "\(message.author?.handle ?? String(localized: "Someone")): \(body)"
        }
        return lounge.topic
    }
}

/// One lounge or direct conversation, kept current while it is on screen.
struct LoungeConversationView: View {
    let client: AppClient
    let id: String
    /// The title from the list, shown until the conversation loads so the bar isn't blank.
    var listedTitle: String?
    @State private var lounge: AppLounge?
    @State private var older: [LoungeMessage] = []
    @State private var olderBefore: Int?
    @State private var loadingOlder = false
    @State private var reply = ""
    @State private var sending = false
    @State private var error: String?
    @State private var atLatest = true
    @State private var voice = VoiceInput()
    @State private var mentions: Mentions?
    /// People the last message mentioned who aren't in the lounge, offered an invite.
    @State private var inviting: [LoungePerson] = []
    @State private var invitingBusy = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var messages: [LoungeMessage] {
        let latest = lounge?.messages ?? []
        let ids = Set(latest.map(\.id))
        return older.filter { !ids.contains($0.id) } + latest
    }

    private var hasOlder: Bool {
        olderBefore != nil || (older.isEmpty && lounge?.has_more == true && lounge?.next_before != nil)
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
                    if let lounge, messages.isEmpty, !hasOlder {
                        intro(lounge)
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        LoungeMessageRow(message: message, continued: continues(index))
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
            .onChange(of: lounge?.messages?.last?.id) { _, _ in
                guard atLatest else { return }
                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("latest", anchor: .bottom) }
            }
        }
        .background(Noora.backgroundPrimary)
        .overlay { if lounge == nil, error == nil { ProgressView() } }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if !inviting.isEmpty, let lounge { inviteBanner(lounge) }
                ReplyComposer(reply: $reply, disabled: lounge == nil, sending: sending, voice: voice,
                              mentions: mentions, place: lounge?.title) {
                    Task { await send() }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle(Text(verbatim: lounge?.title ?? listedTitle ?? ""))
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

    /// Suggests inviting the people a message mentioned who aren't in the lounge.
    private func inviteBanner(_ lounge: AppLounge) -> some View {
        let names = inviting.compactMap { $0.handle.map { "@\($0)" } }.formatted(.list(type: .and))
        return HStack(alignment: .center, spacing: 8) {
            Image(systemName: "person.badge.plus").foregroundStyle(Noora.primary).accessibilityHidden(true)
            Text("\(names) isn’t in \(lounge.title). Invite them?")
                .font(.callout).foregroundStyle(Noora.labelPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Not Now") { inviting = [] }
                .font(.callout).foregroundStyle(Noora.labelSecondary).frame(minHeight: 44)
            Button("Invite") { Task { await invite() } }
                .font(.callout.weight(.semibold)).frame(minHeight: 44)
                .disabled(invitingBusy)
        }
        .padding(.horizontal, 12)
        .interactiveGlass(in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }

    private func invite() async {
        invitingBusy = true
        defer { invitingBusy = false }
        do {
            show(try await client.lounge("invite_lounge", ["id": id, "user_ids": inviting.map(\.id)]))
            inviting = []
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func intro(_ lounge: AppLounge) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: lounge.title).font(.title2.weight(.semibold)).foregroundStyle(Noora.labelPrimary)
            Group {
                if let topic = lounge.topic, lounge.kind == "lounge" {
                    Text(verbatim: topic)
                } else if lounge.kind == "lounge" {
                    Text("This is the start of the lounge. Everyone in your organization can read it.")
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
                show(try await client.lounge("lounge", ["id": id]))
                error = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    /// Shows a newer latest page and marks it read.
    private func show(_ latest: AppLounge) {
        if !older.isEmpty, let previous = lounge?.messages {
            let kept = Set((latest.messages ?? []).map(\.id)).union(older.map(\.id))
            older += previous.filter { !kept.contains($0.id) }
        }
        lounge = latest
        if mentions == nil {
            // Mentions in a lounge suggest invites; in a direct conversation they are only mentions.
            let mentions = Mentions(context: latest.kind == "lounge" ? "lounge" : "direct")
            self.mentions = mentions
            Task { await mentions.load(client) }
        }
        mentions?.members = latest.member_ids ?? latest.members.map(\.id)
        if latest.unread > 0 {
            Task { _ = try? await client.call("read_lounge", ["id": id, "position": latest.last_position]) }
        }
    }

    private func loadOlder() async {
        guard !loadingOlder, let before = olderBefore ?? (older.isEmpty ? lounge?.next_before : nil) else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let page = try await client.lounge("lounge", ["id": id, "before": before])
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
        let absent = mentions?.state.invite ?? []
        do {
            show(try await client.lounge("send_lounge_message", ["id": id, "content": text]))
            reply = ""
            inviting = absent
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

private struct LoungeMessageRow: View {
    let message: LoungeMessage
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

/// Names a new lounge, and optionally what it is for.
private struct NewLoungeView: View {
    let client: AppClient
    let created: (AppLounge) -> Void
    @State private var name = ""
    @State private var topic = ""
    @State private var invites = ""
    @State private var mentions = Mentions(context: "new_lounge")
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
            Section {
                TextField("Invite (type @)", text: $invites, axis: .vertical)
                    .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                    .onChange(of: invites) { _, text in mentions.update(text) }
                MentionBar(mentions: mentions, text: $invites)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 8, trailing: 8))
            }
            if let error {
                Text(verbatim: error).foregroundStyle(Noora.labelDestructive)
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .frame(width: 440, height: 380)
        #endif
        .disabled(creating)
        .task { await mentions.load(client) }
        .navigationTitle("New Lounge")
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
            let lounge = try await client.lounge("create_lounge", [
                "name": name, "topic": topic, "user_ids": mentions.state.loop_in.map(\.id),
            ])
            dismiss()
            created(lounge)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Picks people in the organization to message directly.
private struct NewDirectView: View {
    let client: AppClient
    let created: (AppLounge) -> Void
    @State private var people: [LoungePerson]?
    @State private var chosen: Set<Int> = []
    @State private var search = ""
    @State private var starting = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var matches: [LoungePerson] {
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
                    let data = try await client.call("lounge_people")
                    people = try JSONDecoder().decode([LoungePerson].self, from: JSONSerialization.data(withJSONObject: data["people"] ?? [Any]()))
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
            let lounge = try await client.lounge("start_direct", ["user_ids": chosen.sorted()])
            dismiss()
            created(lounge)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
