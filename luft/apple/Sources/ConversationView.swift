import AVFoundation
import SwiftUI

struct AppMessage: Decodable, Identifiable {
    let id: String
    /// `user`, `assistant`, `tool` or `system`.
    let role: String
    let content: String
    /// The server's order within the thread; absent on replies still queued here.
    var position: Int?
    var toolName: String?
    /// `running` or `complete`.
    var toolStatus: String?
    var createdAt: String?
    /// Who wrote a prompt, in a thread someone was looped into.
    var author: HallPerson?

    var createdDate: Date? {
        guard let createdAt else { return nil }
        return Self.preciseDates.date(from: createdAt) ?? Self.dates.date(from: createdAt)
    }

    private static let dates = ISO8601DateFormatter()
    private static let preciseDates: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    /// A card the model wrote, sized by the Rust core; `content` is its text.
    var ui: AppCard?
    /// The plan the agent shares with `update_progress`, counted by the Rust core;
    /// `content` is the plan as a checklist.
    var progress: AppProgress?
}

struct AppProgress: Decodable {
    struct Step: Decodable {
        let title: String
        /// `pending`, `in_progress` or `completed`.
        let status: String
    }

    let steps: [Step]
    let completed: Int
    let total: Int
    /// The run that shows this plan is still working on it.
    let active: Bool
}

/// What the thread is doing now: the active plan's current step.
struct AppActivity: Decodable {
    let title: String
    let step: Int
    let total: Int
}

struct AppConversation: Decodable {
    let id: String
    let title: String?
    let goal: String?
    /// The server is still answering, decided by the Rust core.
    let working: Bool
    let state: String?
    let messages: [AppMessage]
    /// The current step of the answering run's plan, when it shared one.
    var activity: AppActivity?
    /// The thread's owner and the people looped into it by a mention.
    var owner: HallPerson?
    var participants: [HallPerson]?
    /// Earlier messages stay on the server; `next_before` loads the page before these.
    var has_more: Bool?
    var next_before: Int?
}

struct ThreadRoute: Hashable, Identifiable {
    let id: String
}

extension AppClient {
    func conversation(_ operation: String, _ args: [String: Any]) async throws -> AppConversation {
        let data = try await call(operation, args)
        let conversation = try JSONDecoder().decode(
            AppConversation.self, from: JSONSerialization.data(withJSONObject: data)
        )
        // Starting, replying to and refreshing a conversation all pass here; a
        // cached one can show work that finished since.
        if conversation.working, operation != "cached_thread" { ThreadLiveActivity.shared.threadsWorking() }
        return conversation
    }
}

/// One of the person's own machines a conversation can run on.
struct AppRunner: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let platform: String
    let online: Bool
}

/// Asks what to talk about and where it runs: on Tuist, or on one of the
/// person's runners. The core picks the model.
struct StartConversationView: View {
    /// What the sheet starts with: the keyboard, or dictation from a shortcut.
    enum Input { case text, voice }

    let client: AppClient
    var input = Input.text
    @State private var runners: [AppRunner] = []
    /// Nil runs the conversation on Tuist.
    @State private var runner: String?
    @State private var content = ""
    @State private var starting = false
    @State private var error: String?
    @State private var request: Task<Void, Never>?
    @FocusState private var focused: Bool
    // Observed: the field, Start and the dictation bar follow its phase.
    @StateObject private var voice = VoiceInput()
    @State private var dictationStarted = false
    @State private var mentions = Mentions(context: "new_thread")
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section {
                TextField("What do you want to talk about?", text: $content, axis: .vertical)
                    .lineLimit(4 ... 12)
                    .focused($focused)
                    .disabled(starting || voice.busy)
                    .onChange(of: content) { _, text in mentions.update(text) }
                MentionBar(mentions: mentions, text: $content)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 8, trailing: 8))
            } footer: {
                if mentions.people.isEmpty == false, mentions.state.loop_in.isEmpty {
                    Text("Type @ to loop someone in.")
                }
            }
            if let message = voice.errorMessage {
                Text(verbatim: message).foregroundStyle(Noora.labelDestructive)
            }
            if !runners.isEmpty {
                Picker("Run on", selection: $runner) {
                    Text("Tuist").tag(String?.none)
                    ForEach(runners) { runner in
                        Text(verbatim: runner.online
                            ? runner.name
                            : String(format: String(localized: "%@ (offline)"), runner.name))
                            .tag(Optional(runner.id))
                    }
                }
                .disabled(starting || voice.busy)
            }
            if let error {
                Text(verbatim: error).foregroundStyle(Noora.labelDestructive)
            }
        }
        .task { await mentions.load(client) }
        // People without runners see no choice; a failure to list them changes nothing.
        .task {
            if let data = try? await client.call("runners"),
               let list = data["runners"],
               let decoded = try? JSONDecoder().decode([AppRunner].self, from: JSONSerialization.data(withJSONObject: list))
            { runners = decoded }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .frame(width: 480, height: 320)
        #endif
        .navigationTitle("New conversation")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(starting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { request = Task { await start() } }
                        .disabled(starting || voice.busy || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            // Dictation adds editable text to the topic; only Start sends it.
            .safeAreaInset(edge: .bottom) {
                if voice.busy {
                    ReplyComposer(reply: $content, disabled: true, sending: starting, voice: voice) {}
                        .padding()
                }
            }
            .interactiveDismissDisabled(starting)
            .onAppear { if input == .text { focused = true } }
            .onChange(of: voice.busy) { _, busy in if !busy { focused = true } }
            // Dictate from a shortcut while the sheet is already open switches it to dictation.
            .onChange(of: input) { _, input in
                if input == .voice {
                    dictationStarted = false
                    beginRequestedDictation()
                } else if !voice.busy {
                    focused = true
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                beginRequestedDictation()
                // Permission alerts briefly deactivate the scene before their callbacks return.
                if phase == .background || (phase == .inactive && voice.phase != .requesting) { voice.cancel() }
            }
            .onReceive(NotificationCenter.default.publisher(for: audioInterruption)) { _ in voice.cancel() }
            .onDisappear { request?.cancel(); voice.cancel() }
    }

    /// A shortcut can open the sheet before the app is active; the microphone waits for it.
    private func beginRequestedDictation() {
        guard input == .voice, scenePhase == .active, !dictationStarted else { return }
        dictationStarted = true
        voice.begin()
    }

    private func start() async {
        starting = true
        defer { starting = false }
        let generation = client.view.generation
        let revision = client.view.navigation.revision
        do {
            var args: [String: Any] = ["content": content]
            if let runner { args["runner_id"] = runner }
            let thread = try await client.conversation("start_thread", args)
            guard !Task.isCancelled, generation == client.view.generation,
                  revision == client.view.navigation.revision else { return }
            // The core also checks these versions when this queued call executes.
            _ = try await client.call("navigate", [
                "url": "/threads/\(thread.id)", "if_generation": generation, "if_revision": revision,
            ])
            guard !Task.isCancelled else { return }
            dismiss()
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}

/// One conversation, kept current while the server is answering.
struct ConversationView: View {
    let client: AppClient
    let id: String
    @State private var thread: AppConversation?
    /// Pages loaded before the latest messages, oldest first.
    @State private var older: [AppMessage] = []
    @State private var olderBefore: Int?
    @State private var loadingOlder = false
    @State private var reply = ""
    @State private var sending = false
    @State private var error: String?
    @State private var showingPrompts = false
    @State private var chosenPrompt: String?
    @State private var pendingJump: String?
    /// Whether the end of the conversation is on screen; new messages only scroll while it is.
    @State private var atLatest = true
    // Not observed here: only the composer redraws as dictation levels change.
    @State private var voice = VoiceInput()
    @State private var mentions = Mentions(context: "thread")
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Shared threads name who wrote each prompt.
    private var shared: Bool { thread?.participants?.isEmpty == false }

    /// Earlier pages, then the latest messages, without repeats where they overlap.
    private var messages: [AppMessage] {
        let latest = thread?.messages ?? []
        let ids = Set(latest.map(\.id))
        return older.filter { !ids.contains($0.id) } + latest
    }

    private var hasOlder: Bool {
        olderBefore != nil || (older.isEmpty && thread?.has_more == true && thread?.next_before != nil)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if hasOlder {
                        Button(loadingOlder ? LocalizedStringKey("Loading earlier messages…") : LocalizedStringKey("Load earlier messages")) {
                            Task { await loadOlder() }
                        }
                        .disabled(loadingOlder)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    ForEach(MessageGroup.groups(messages)) { group in
                        switch group {
                        // A card can call `reply` without a tap (on mount, from a timer),
                        // so its text goes to the composer and the person sends it.
                        case let .message(message): MessageRow(message: message, showAuthor: shared) { text in reply = text }.id(message.id)
                        case let .tools(tools): ToolActivity(tools: tools).id(tools[0].id)
                        }
                    }
                    if thread?.working == true {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            if let activity = thread?.activity {
                                Text(verbatim: activity.title).foregroundStyle(Noora.labelPrimary).lineLimit(1)
                                Text("Step \(activity.step) of \(activity.total)")
                                    .font(.caption).foregroundStyle(Noora.labelSecondary)
                            } else {
                                Text("Thinking…").foregroundStyle(Noora.labelSecondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
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
            .onChange(of: thread?.messages.last?.id) { previous, _ in
                // Someone reading earlier history, or who jumped to a prompt, stays where they are.
                guard atLatest else { return }
                // The first messages open at the end; only later ones animate in.
                withAnimation(previous == nil || reduceMotion ? nil : .default) { proxy.scrollTo("latest", anchor: .bottom) }
            }
            .onChange(of: pendingJump) { _, target in
                guard let target else { return }
                pendingJump = nil
                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(target, anchor: .top) }
            }
        }
        .background(Noora.backgroundPrimary)
        .overlay { if thread == nil, error == nil { ProgressView() } }
        .safeAreaInset(edge: .bottom) {
            ReplyComposer(reply: $reply, disabled: thread?.working != false, sending: sending, voice: voice, mentions: mentions) {
                Task { await send() }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle(Text(verbatim: thread?.title ?? thread?.goal ?? ""))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
        #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingPrompts = true } label: {
                        Label("Prompts", systemImage: "list.bullet")
                    }
                    .help("Prompts")
                    .accessibilityHint("Choose a prompt to jump back to it")
                    .disabled(thread == nil)
                }
            }
            // Jump only once the sheet is gone, so the scroll is not lost under it.
            .sheet(isPresented: $showingPrompts, onDismiss: {
                if let target = chosenPrompt {
                    chosenPrompt = nil
                    pendingJump = target
                }
            }) {
                PromptIndex(
                    prompts: messages.filter { $0.role == "user" },
                    hasOlder: hasOlder,
                    loading: loadingOlder,
                    older: { await loadOlder() },
                    choose: { target in
                        chosenPrompt = target
                        showingPrompts = false
                    }
                )
            }
            .task(id: id) { await follow() }
            .task { await mentions.load(client) }
            .toolbar {
                if shared, let thread {
                    ToolbarItem(placement: .status) { ParticipantsLabel(owner: thread.owner, participants: thread.participants ?? []) }
                }
            }
            // The live socket: server changes and the agent's calls to this app's tools.
            .task(id: id) { await client.live(id) { await reload() } }
            // Unaccepted dictation never survives leaving the conversation or the app.
            .onChange(of: scenePhase) { _, phase in
                // Permission alerts briefly deactivate the scene before their callbacks return.
                if phase == .background || (phase == .inactive && voice.phase != .requesting) { voice.cancel() }
            }
            .onReceive(NotificationCenter.default.publisher(for: audioInterruption)) { _ in voice.cancel() }
            .onDisappear { voice.cancel() }
    }

    /// Shows a newer latest page. Once earlier pages are loaded, messages that
    /// scroll off the latest page join them, so none fall between the two.
    private func show(_ latest: AppConversation) {
        if !older.isEmpty, let previous = thread?.messages {
            let kept = Set(latest.messages.map(\.id)).union(older.map(\.id))
            older += previous.filter { $0.position != nil && !kept.contains($0.id) }
        }
        thread = latest
        // Mentioning someone already in the thread loops in nobody new.
        mentions.members = ([latest.owner] + (latest.participants ?? [])).compactMap { $0?.id }
    }

    /// Loads the conversation, then polls while the server is answering.
    private func follow() async {
        thread = try? await client.conversation("cached_thread", ["id": id])
        while !Task.isCancelled {
            do {
                show(try await client.conversation("thread", ["id": id]))
                error = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            try? await Task.sleep(for: thread?.working == true ? .seconds(2) : .seconds(15))
        }
    }

    /// Loads the conversation again when the server says it changed.
    private func reload() async {
        if let latest = try? await client.conversation("thread", ["id": id]) { show(latest) }
    }

    /// Loads the page before the earliest message shown. Only the latest page is kept offline.
    private func loadOlder() async {
        guard !loadingOlder, let before = olderBefore ?? (older.isEmpty ? thread?.next_before : nil) else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let page = try await client.conversation("thread", ["id": id, "before": before])
            let known = Set(messages.map(\.id))
            older = page.messages.filter { !known.contains($0.id) } + older
            olderBefore = page.has_more == true ? page.next_before : nil
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Sends the composer's text.
    private func send() async {
        let text = reply
        guard !sending, !voice.busy, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            show(try await client.conversation("send_message", ["id": id, "content": text]))
            reply = ""
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A message, or consecutive tool calls shown together as one disclosure.
private enum MessageGroup: Identifiable {
    case message(AppMessage)
    case tools([AppMessage])

    var id: String {
        switch self {
        case let .message(message): message.id
        case let .tools(tools): "tools-" + tools[0].id
        }
    }

    static func groups(_ messages: [AppMessage]) -> [MessageGroup] {
        var groups: [MessageGroup] = []
        for message in messages {
            if message.role == "tool" {
                if case let .tools(tools) = groups.last {
                    groups[groups.count - 1] = .tools(tools + [message])
                } else {
                    groups.append(.tools([message]))
                }
            } else {
                groups.append(.message(message))
            }
        }
        return groups
    }
}

/// Lists the person's prompts in the loaded history; choosing one jumps back to it.
private struct PromptIndex: View {
    let prompts: [AppMessage]
    let hasOlder: Bool
    let loading: Bool
    let older: () async -> Void
    let choose: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if hasOlder {
                    Button(loading ? LocalizedStringKey("Loading earlier prompts…") : LocalizedStringKey("Load earlier prompts")) { Task { await older() } }
                        .disabled(loading).frame(minHeight: 44)
                }
                if prompts.isEmpty {
                    Text("No prompts in loaded history.").foregroundStyle(Noora.labelSecondary)
                }
                ForEach(prompts) { message in
                    Button { choose(message.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: message.content.trimmingCharacters(in: .whitespacesAndNewlines))
                                .lineLimit(2).multilineTextAlignment(.leading)
                                .foregroundStyle(Noora.labelPrimary)
                            if let date = message.createdDate {
                                Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                                    .font(.caption).foregroundStyle(Noora.labelSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Jump to this message")
                }
            }
            .navigationTitle("Prompts")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .frame(idealWidth: 380, idealHeight: 440)
        .presentationDetents([.medium, .large])
    }
}

/// Tool calls as expandable evidence: a summary that says whether they are
/// still running, and each call's name, state and result on request.
private struct ToolActivity: View {
    let tools: [AppMessage]
    @State private var expanded = false

    private var running: Bool { tools.contains { $0.toolStatus == "running" } }

    var body: some View {
        if tools.count == 1 {
            ToolCallRow(tool: tools[0])
        } else {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tools) { ToolCallRow(tool: $0) }
                }
                .padding(.leading, 12).padding(.top, 8)
                .overlay(alignment: .leading) { Rectangle().fill(Noora.border).frame(width: 1) }
            } label: {
                HStack(spacing: 8) {
                    ToolStatusIcon(running: running)
                    Text(running ? LocalizedStringKey("Using \(tools.count) tools…") : LocalizedStringKey("Used \(tools.count) tools"))
                        .font(.subheadline.weight(.medium)).foregroundStyle(Noora.labelPrimary)
                }
                .frame(minHeight: 44)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ToolCallRow: View {
    let tool: AppMessage
    @State private var expanded = false

    private var running: Bool { tool.toolStatus == "running" }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Result").font(.caption.bold()).foregroundStyle(Noora.labelSecondary)
                Text(verbatim: tool.content).font(.caption.monospaced()).textSelection(.enabled)
                    .foregroundStyle(Noora.labelPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        } label: {
            HStack(spacing: 8) {
                ToolStatusIcon(running: running)
                Text(verbatim: tool.toolName ?? String(localized: "Tool"))
                    .font(.subheadline.monospaced()).foregroundStyle(Noora.labelPrimary).lineLimit(1)
                Text(running ? LocalizedStringKey("Running") : LocalizedStringKey("Done")).font(.caption).foregroundStyle(Noora.labelSecondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .disabled(running)
        .padding(.horizontal, 12)
        .background(Noora.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noora.border, lineWidth: 1))
    }
}

private struct ToolStatusIcon: View {
    let running: Bool

    var body: some View {
        if running {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: "wrench.and.screwdriver").foregroundStyle(Noora.labelSecondary)
                .accessibilityHidden(true)
        }
    }
}

/// The agent's plan as a checklist it updates in place: done steps checked,
/// the current one spinning while its run works, the rest open.
private struct PlanView: View {
    let progress: AppProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Plan").font(.subheadline.weight(.medium)).foregroundStyle(Noora.labelPrimary)
                Spacer()
                Text("\(progress.completed) of \(progress.total) done")
                    .font(.caption).foregroundStyle(Noora.labelSecondary)
            }
            ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
                .tint(Noora.primary)
            ForEach(Array(progress.steps.enumerated()), id: \.offset) { _, step in
                // Centered: the spinner has no text baseline to align with.
                HStack(spacing: 8) {
                    icon(step.status).frame(width: 18)
                    Text(verbatim: step.title)
                        .font(.subheadline)
                        .foregroundStyle(step.status == "completed" ? Noora.labelSecondary : Noora.labelPrimary)
                        .strikethrough(step.status == "completed", color: Noora.labelSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(Text(label(step.status)))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Noora.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noora.border, lineWidth: 1))
    }

    @ViewBuilder
    private func icon(_ status: String) -> some View {
        switch status {
        case "completed":
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Noora.primary).accessibilityHidden(true)
        case "in_progress" where progress.active:
            ProgressView().controlSize(.mini)
        case "in_progress":
            Image(systemName: "circle.lefthalf.filled").foregroundStyle(Noora.labelSecondary).accessibilityHidden(true)
        default:
            Image(systemName: "circle").foregroundStyle(Noora.labelSecondary).accessibilityHidden(true)
        }
    }

    private func label(_ status: String) -> LocalizedStringKey {
        switch status {
        case "completed": "Completed"
        case "in_progress": "In progress"
        default: "Not started"
        }
    }
}

struct MessageRow: View {
    let message: AppMessage
    /// Names who wrote a prompt, in a thread shared with others.
    var showAuthor = false
    /// Puts a card's reply in the composer.
    let reply: (String) -> Void

    var body: some View {
        if let card = message.ui {
            CardView(card: card, fallback: message.content, reply: reply)
        } else if let progress = message.progress {
            PlanView(progress: progress)
        } else {
            text
        }
    }

    @ViewBuilder
    private var text: some View {
        switch message.role {
        case "user":
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 2) {
                    if showAuthor, let handle = message.author?.handle {
                        Text(verbatim: "@\(handle)").font(.caption.weight(.semibold)).foregroundStyle(Noora.labelSecondary)
                    }
                    Text(verbatim: message.content)
                        .textSelection(.enabled)
                        .foregroundStyle(Noora.labelPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Noora.neutralHover, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noora.border, lineWidth: 1))
                }
                .accessibilityElement(children: .combine)
            }
        case "assistant":
            Text(markdown(message.content)).textSelection(.enabled).foregroundStyle(Noora.labelPrimary)
        default:
            Text(verbatim: message.content).font(.caption).foregroundStyle(Noora.labelSecondary)
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

/// Calls and other audio sessions end dictation, in replies and in Start conversation.
private var audioInterruption: Notification.Name {
    #if os(macOS)
        .AVAudioEngineConfigurationChange
    #else
        AVAudioSession.interruptionNotification
    #endif
}

/// Who is in a shared thread: its owner, whose subscription runs it, and the people looped in.
private struct ParticipantsLabel: View {
    let owner: HallPerson?
    let participants: [HallPerson]

    var body: some View {
        let names = ([owner] + participants).compactMap { $0?.handle }
        Label {
            Text(verbatim: names.map { "@\($0)" }.formatted(.list(type: .and)))
                .lineLimit(1)
        } icon: { Image(systemName: "person.2.fill") }
            .labelStyle(.titleAndIcon)
            .font(.caption).foregroundStyle(Noora.labelSecondary)
            .accessibilityLabel(Text("Shared with \(names.formatted(.list(type: .and)))"))
    }
}
