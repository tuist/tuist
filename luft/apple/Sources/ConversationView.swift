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
    var author: LoungePerson?
    var attachments: [PromptAttachment]?

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
    var decision: AppDecision?
    /// The plan the agent shares with `update_progress`, counted by the Rust core;
    /// `content` is the plan as a checklist.
    var progress: AppProgress?
    /// A Bash call's Struo build or test progress, presented by the Rust core;
    /// `content` says it in words.
    var build: AppBuild?
    var toolResult: AppToolResult?
}

struct AppToolResult: Decodable {
    struct TestCase: Decodable {
        let name: String
        let module: String?
        let suite: String?
        let flaky: Bool?
        let state: String?
    }
    let text: String
    let preview: String
    let raw: String
    let testCases: [TestCase]?
}

struct AppBuild: Decodable {
    struct Tests: Decodable {
        let passed: Int
        let failed: Int
        let skipped: Int
    }

    /// `build` or `test`.
    let command: String
    let target: String?
    let planned: Int
    let done: Int
    let cached: Int
    let failed: Int
    /// Case counts, once a case ran.
    let tests: Tests?
    /// The share of planned targets done, once Struo planned them.
    let fraction: Double?
    /// A target or test case failed.
    let failing: Bool
    /// The build still runs in a working thread.
    let active: Bool
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
    var reauthorization_required: Bool?
    var can_reauthorize: Bool?
    /// Set while the person snoozed it, decided by the Rust core.
    var snooze: AppSnooze?
    /// The current step of the answering run's plan, when it shared one.
    var activity: AppActivity?
    /// The core exposes this only for a live, ready sandbox residency.
    var workspace_ready_id: String?
    /// The thread's owner and the people looped into it by a mention.
    var owner: LoungePerson?
    var participants: [LoungePerson]?
    /// Earlier messages stay on the server; `next_before` loads the page before these.
    var has_more: Bool?
    var next_before: Int?
    var section: String?
    var provider: String?
    var model: String?
    var repository: String?
    var branch: String?
    var runner_id: String?
    /// Editable next prompts selected by the core from the latest answer.
    var suggestions: [String]?
    var suggestion_icons: [String: String]?
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
/// person's runners. The core picks the model. A sheet on the Mac; the
/// iPhone's default chat screen.
struct StartConversationView: View {
    /// What it starts with: the keyboard, or dictation from a shortcut. Nil
    /// leaves the iPhone's chat screen as it is, without raising the keyboard.
    enum Input { case text, voice }

    let client: AppClient
    var input: Input? = .text
    @State private var runners: [AppRunner] = []
    /// Nil runs the conversation on Tuist.
    @State private var runner: String?
    @State private var content = ""
    @State private var attachments: [PromptAttachment] = []
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
        layout
            .task { await mentions.load(client) }
            // People without runners see no choice; a failure to list them changes nothing.
            .task {
                if let data = try? await client.call("runners"),
                   let list = data["runners"],
                   let decoded = try? JSONDecoder().decode([AppRunner].self, from: JSONSerialization.data(withJSONObject: list))
                { runners = decoded }
            }
            .onAppear { if input == .text { focused = true } }
            .onChange(of: voice.busy) { _, busy in if !busy { focused = true } }
            // Dictate from a shortcut while it is already open switches it to dictation.
            .onChange(of: input) { _, input in
                if input == .voice {
                    dictationStarted = false
                    beginRequestedDictation()
                } else if input == .text, !voice.busy {
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

    #if os(iOS)
        /// The iPhone's default chat screen: nothing is open yet, and sending starts a conversation.
        private var layout: some View {
            VStack(spacing: 12) {
                Image("TuistRoundedIcon").resizable().frame(width: 56, height: 56).accessibilityHidden(true)
                Text("Big things start here").font(.title2.weight(.semibold)).foregroundStyle(Noora.labelPrimary)
                Text("Ask a question, explore an idea, or solve a problem with Tuist.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Noora.labelSecondary)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Noora.backgroundPrimary)
            .contentShape(Rectangle())
            .onTapGesture { focused = false }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    if let error {
                        Text(verbatim: error).font(.caption).foregroundStyle(Noora.labelDestructive)
                            .padding(.horizontal, 12)
                    } else if mentionHint {
                        Text("Type @ to loop someone in.").font(.caption).foregroundStyle(Noora.labelSecondary)
                            .padding(.horizontal, 12)
                    }
                    ReplyComposer(
                        reply: $content, disabled: false, sending: starting, voice: voice, mentions: mentions,
                        placeholder: "What do you want to talk about?", focus: $focused, attachments: $attachments
                    ) { request = Task { await start() } }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .navigationTitle(Text(verbatim: "Luft"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !runners.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Run on", selection: $runner) { runnerOptions }
                        } label: {
                            Label("Run on", systemImage: "desktopcomputer")
                        }
                        .disabled(starting || voice.busy)
                    }
                }
            }
        }
    #else
        private var layout: some View {
            Form {
                Section {
                    ReplyComposer(
                        reply: $content, disabled: false, sending: starting, voice: voice, mentions: mentions,
                        placeholder: "What do you want to talk about?", focus: $focused, attachments: $attachments
                    ) { request = Task { await start() } }
                } footer: {
                    if mentionHint { Text("Type @ to loop someone in.") }
                }
                if !runners.isEmpty {
                    Picker("Run on", selection: $runner) { runnerOptions }
                        .disabled(starting || voice.busy)
                }
                if let error {
                    Text(verbatim: error).foregroundStyle(Noora.labelDestructive)
                }
            }
            .formStyle(.grouped)
            .frame(width: 480, height: 320)
            .navigationTitle("New conversation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(starting)
                }
            }
            .interactiveDismissDisabled(starting)
        }
    #endif

    /// Someone from the organization could be looped in, and nobody is yet.
    private var mentionHint: Bool {
        !mentions.people.isEmpty && mentions.state.loop_in.isEmpty && mentions.state.query == nil
    }

    @ViewBuilder private var runnerOptions: some View {
        Text("Tuist").tag(String?.none)
        ForEach(runners) { runner in
            Text(verbatim: runner.online
                ? runner.name
                : String(format: String(localized: "%@ (offline)"), runner.name))
                .tag(Optional(runner.id))
        }
    }

    /// A shortcut can open the sheet before the app is active; the microphone waits for it.
    private func beginRequestedDictation() {
        guard input == .voice, scenePhase == .active, !dictationStarted else { return }
        dictationStarted = true
        voice.begin()
    }

    private func start() async {
        guard !starting, !voice.busy,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else { return }
        starting = true
        defer { starting = false }
        let generation = client.view.generation
        let revision = client.view.navigation.revision
        do {
            var args: [String: Any] = ["content": content, "attachments": attachments.map(\.payload)]
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
    @State private var attachments: [PromptAttachment] = []
    @FocusState private var replyFocused: Bool
    @State private var sending = false
    @State private var error: String?
    @State private var showingPrompts = false
    @State private var chosenPrompt: String?
    @State private var pendingJump: String?
    @State private var snoozeChoices = SnoozeChoices()
    @State private var pickingSnoozeTime = false
    @State private var showingDetails = false
    @State private var confirmingArchive = false
    @State private var updatingArchive = false
    /// The server answered for this thread at least once: a thread never opened here
    /// has no cached state, so whether it works isn't known before.
    @State private var live = false
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
                        case let .message(message):
                            MessageRow(message: message, showAuthor: shared, answering: sending || thread?.reauthorization_required == true, answer: { option in
                                Task { await answer(message, option: option) }
                            }) { text in reply = text }.id(message.id)
                        case let .tools(tools): ToolActivity(tools: tools).id(tools[0].id)
                        }
                    }
                    if thread?.working == true {
                        HStack(spacing: 8) {
                            WorkingIndicator()
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
        .safeAreaInset(edge: .top) {
            if let current = thread?.snooze {
                HStack(spacing: 8) {
                    Image(systemName: "moon.zzz").foregroundStyle(Noora.primary).accessibilityHidden(true)
                    Text(verbatim: current.label).font(.subheadline).foregroundStyle(Noora.labelPrimary)
                    Spacer()
                    Button("Wake") { Task { await snooze(until: nil) } }.font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .interactiveGlass(in: Capsule())
                .padding(.horizontal).padding(.top, 4)
            }
        }
        .overlay { if thread == nil, error == nil { ProgressView() } }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .trailing, spacing: 8) {
                if thread?.reauthorization_required == true {
                    Text("The owner must authorize future messages with their current sign-in. This does not resume previous work.")
                        .font(.callout).foregroundStyle(Noora.labelSecondary)
                    if thread?.can_reauthorize == true {
                        Button("Authorize future messages") {
                            Task { await reauthorize() }
                        }
                        .disabled(sending)
                    }
                }
                #if os(iOS)
                    if thread?.workspace_ready_id != nil {
                        Label("Sandbox ready", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(Noora.labelSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                #endif
                HStack(spacing: 8) {
                    if reply.isEmpty, !sending, !voice.busy, let suggestions = thread?.suggestions, !suggestions.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(Array(suggestions.enumerated()), id: \.offset) { _, suggestion in
                                    Button {
                                        reply = suggestion
                                        replyFocused = true
                                    } label: {
                                        HStack(spacing: 6) {
                                            if let icon = thread?.suggestion_icons?[suggestion],
                                               let symbol = ["investigate": "magnifyingglass", "test": "checkmark.circle", "explain": "text.bubble", "retry": "arrow.clockwise"][icon] {
                                                Image(systemName: symbol).accessibilityHidden(true)
                                            }
                                            Text(verbatim: suggestion).lineLimit(1)
                                        }
                                        .font(.subheadline)
                                        .padding(.horizontal, 14)
                                        .frame(minHeight: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Noora.labelPrimary)
                                    .interactiveGlass(in: Capsule())
                                }
                            }
                            .padding(4)
                        }
                        .scrollIndicators(.hidden)
                    }
                    #if os(iOS)
                        // Floats over the messages, right above Send, so it is in reach of the thumb.
                        Spacer(minLength: 0)
                        promptsButton
                            .labelStyle(.iconOnly)
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 44, height: 44)
                            .interactiveGlass(in: Circle())
                            .padding(.trailing, 4)
                    #endif
                }
                ReplyComposer(reply: $reply, disabled: thread?.working != false || thread?.reauthorization_required == true, sending: sending, voice: voice, mentions: mentions, focus: $replyFocused, attachments: $attachments) {
                    Task { await send() }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background {
            Noora.backgroundPrimary
            #if os(iOS)
                .overlay { SandboxReadyEffect(residency: thread?.workspace_ready_id) }
            #endif
        }
        .navigationTitle(Text(verbatim: thread?.title ?? thread?.goal ?? ""))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Session details", systemImage: "info.circle") { showingDetails = true }
                        if thread?.section != "archived" {
                            Menu {
                                SnoozeButtons(
                                    choices: snoozeChoices,
                                    working: thread?.working == true,
                                    snoozed: thread?.snooze != nil,
                                    snooze: { until in Task { await snooze(until: until) } },
                                    custom: { pickingSnoozeTime = true }
                                )
                            } label: {
                                Label("Snooze", systemImage: thread?.snooze == nil ? "moon.zzz" : "moon.zzz.fill")
                            }
                        }
                        Divider()
                        if thread?.section == "archived" {
                            Button("Restore", systemImage: "tray.and.arrow.up") { Task { await archive(false) } }
                        } else {
                            Button("Archive", systemImage: "archivebox", role: .destructive) { confirmingArchive = true }
                        }
                    } label: {
                        Label("Session actions", systemImage: "ellipsis")
                    }
                    .help("Session actions")
                    .accessibilityIdentifier("session-actions")
                    .disabled(thread == nil || updatingArchive)
                }
                #if os(macOS)
                    ToolbarItem(placement: .primaryAction) { promptsButton }
                #endif
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
                // Shared threads list who is in them under the title, like a group chat.
                if shared, let thread {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 1) {
                            Text(verbatim: thread.title ?? thread.goal ?? "")
                                .font(.headline).lineLimit(1)
                            ParticipantsLabel(owner: thread.owner, participants: thread.participants ?? [])
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .task { await snoozeChoices.follow(client) }
            // The Live Activity's Snooze opens the thread with its choices over it. Dialog
            // buttons take the presenting view's tint; the choices read as plain text.
            .background {
                Color.clear.confirmationDialog(
                    "Snooze", isPresented: Binding(
                        get: { client.view.navigation.snooze && client.view.navigation.thread_id == id && live },
                        set: { if !$0 { leaveSnoozeChoices() } }
                    ), titleVisibility: .visible
                ) {
                    SnoozeButtons(
                        choices: snoozeChoices,
                        working: thread?.working == true,
                        snoozed: thread?.snooze != nil,
                        inline: true,
                        snooze: { until in Task { await snooze(until: until) } },
                        custom: { pickingSnoozeTime = true }
                    )
                } message: {
                    Text(verbatim: thread?.title ?? thread?.goal ?? "")
                }
                .tint(Noora.labelPrimary)
            }
            .sheet(isPresented: $pickingSnoozeTime) {
                CustomSnoozeView { until in Task { await snooze(until: until) } }
            }
            .sheet(isPresented: $showingDetails) {
                if let thread { SessionDetails(thread: thread) }
            }
            .alert("Archive Thread?", isPresented: $confirmingArchive) {
                Button("Cancel", role: .cancel) {}
                Button("Archive", role: .destructive) { Task { await archive(true) } }
            } message: {
                Text(thread?.working == true
                    ? "Its run stops. You can find it under Archived."
                    : "You can find it under Archived.")
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

    /// Lists the person's earlier messages to jump back to.
    private var promptsButton: some View {
        Button { showingPrompts = true } label: {
            Label("Prompts", systemImage: "list.bullet")
        }
        .help("Prompts")
        .accessibilityHint("Choose a prompt to jump back to it")
        .disabled(thread == nil)
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
                live = true
                error = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            try? await Task.sleep(for: thread?.working == true ? .seconds(2) : .seconds(15))
        }
    }

    /// Snoozes or wakes the thread. A snoozed thread is out of the way, so
    /// snoozing it returns to the inbox; waking it stays here.
    private func snooze(until: String?) async {
        do {
            show(try await client.snooze(id, until: until))
            if until != nil { await client.perform("navigation_back") } else { leaveSnoozeChoices() }
        } catch {
            self.error = error.localizedDescription
            leaveSnoozeChoices()
        }
    }

    private func reauthorize() async {
        guard !sending else { return }
        sending = true
        defer { sending = false }
        do {
            show(try await client.conversation("reauthorize_thread", ["id": id, "consent": true]))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func archive(_ archived: Bool) async {
        guard !updatingArchive else { return }
        updatingArchive = true
        defer { updatingArchive = false }
        do {
            show(try await client.conversation("archive_thread", ["id": id, "archived": archived]))
            if archived { await client.perform("navigation_back") }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Closes the choices the Live Activity opened, keeping the thread open.
    private func leaveSnoozeChoices() {
        guard client.view.navigation.snooze else { return }
        Task { await client.perform("navigate", ["url": "/threads/\(id)"]) }
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

    private func answer(_ message: AppMessage, option: String?) async {
        guard !sending, let decision = message.decision, decision.status == "pending" else { return }
        var args: [String: Any] = ["id": id, "question_id": message.id]
        if let option {
            guard let choice = decision.options.first(where: { $0.id == option }) else { return }
            args["option_id"] = option
            args["content"] = choice.label
        } else {
            args["cancel"] = true
            args["content"] = String(localized: "Dismissed")
        }
        sending = true
        defer { sending = false }
        do {
            show(try await client.conversation("answer_question", args))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Sends the composer's text.
    private func send() async {
        let text = reply
        guard !sending, !voice.busy, thread?.working == false,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            show(try await client.conversation("send_message", ["id": id, "content": text, "attachments": attachments.map(\.payload)]))
            reply = ""
            attachments = []
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

struct ToolCallRow: View {
    let tool: AppMessage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var expanded = false
    @State private var showAll = false
    @State private var showRaw = false

    private var running: Bool { tool.toolStatus == "running" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        ToolStatusIcon(running: running)
                    }
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                        : AnyLayout(HStackLayout(spacing: 8))
                    layout {
                        Text(verbatim: tool.toolName ?? String(localized: "Tool"))
                            .font(.subheadline.weight(.medium)).foregroundStyle(Noora.labelPrimary)
                        Text(running ? LocalizedStringKey("Running") : LocalizedStringKey("Done"))
                            .font(.caption).foregroundStyle(Noora.labelSecondary)
                            .fixedSize(horizontal: true, vertical: true)
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(running)
            .accessibilityValue(expanded ? Text("Expanded") : Text("Collapsed"))
            if let build = tool.build {
                BuildProgressView(build: build).padding(.bottom, 10)
            }
            if expanded {
                if let cases = tool.toolResult?.testCases {
                    Text("\(cases.count) test cases").font(.caption).foregroundStyle(Noora.labelSecondary)
                    ForEach(Array((showAll ? cases : Array(cases.prefix(3))).enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: item.name).font(.subheadline.weight(.medium))
                            if let suite = item.suite { Text(verbatim: suite).font(.caption).foregroundStyle(Noora.labelSecondary) }
                            if let module = item.module { Text(verbatim: module).font(.caption).foregroundStyle(Noora.labelSecondary) }
                            HStack {
                                if item.flaky == true { Text("Flaky").foregroundStyle(Noora.labelDestructive) }
                                if let state = item.state { Text(verbatim: state).foregroundStyle(Noora.labelSecondary) }
                            }.font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Noora.backgroundPrimary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    if cases.count > 3 { moreButton }
                } else {
                    Text(verbatim: showAll ? (tool.toolResult?.text ?? tool.content) : (tool.toolResult?.preview ?? tool.content))
                        .font(.caption.monospaced()).textSelection(.enabled)
                        .lineLimit(showAll ? nil : 8)
                    // Wrapped lines can overflow even a short source string.
                    moreButton
                }
                Divider().padding(.vertical, 4)
                Button { showRaw.toggle() } label: {
                    Label(showRaw ? LocalizedStringKey("Hide raw result") : LocalizedStringKey("Raw result"), systemImage: "curlybraces")
                        .font(.caption).frame(minHeight: 44)
                }.buttonStyle(.borderless)
                if showRaw {
                    ScrollView([.horizontal, .vertical]) {
                        Text(verbatim: tool.toolResult?.raw ?? tool.content)
                            .font(.caption.monospaced()).textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: true).padding(8)
                    }.frame(height: 200)
                        .background(Noora.backgroundPrimary, in: RoundedRectangle(cornerRadius: 8))
                    ShareLink(item: tool.content) {
                        Label("Share raw result", systemImage: "square.and.arrow.up").font(.caption).frame(minHeight: 44)
                    }.buttonStyle(.borderless)
                }
                Spacer(minLength: 6)
            }
        }
        .foregroundStyle(Noora.labelPrimary)
        .padding(.horizontal, 12)
        .background(Noora.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noora.border, lineWidth: 1))
    }

    private var moreButton: some View {
        Button(showAll ? LocalizedStringKey("Show less") : LocalizedStringKey("Show more")) { showAll.toggle() }
            .font(.caption).frame(minHeight: 44).buttonStyle(.borderless)
    }
}

/// A Struo build or test a Bash call runs: what it builds, how many of its
/// planned targets are done and, for tests, how the cases went.
private struct BuildProgressView: View {
    let build: AppBuild

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(build.command == "test" ? LocalizedStringKey("Testing with Struo") : LocalizedStringKey("Building with Struo"))
                    .font(.caption.weight(.medium)).foregroundStyle(Noora.labelPrimary)
                if let target = build.target, !target.isEmpty {
                    Text(verbatim: target).font(.caption.monospaced()).foregroundStyle(Noora.labelSecondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 4)
                if build.planned > 0 {
                    Text("\(build.done) of \(build.planned) targets")
                        .font(.caption).monospacedDigit().foregroundStyle(Noora.labelSecondary)
                        .contentTransition(.numericText())
                }
            }
            if let fraction = build.fraction {
                ProgressView(value: fraction)
                    .tint(build.failing ? Noora.labelDestructive : Noora.primary)
                    .animation(.default, value: fraction)
            } else if build.active {
                ProgressView().progressViewStyle(.linear)
            }
            if let tests = build.tests {
                Text("\(tests.passed) passed, \(tests.failed) failed, \(tests.skipped) skipped")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(tests.failed > 0 ? Noora.labelDestructive : Noora.labelSecondary)
            }
        }
        .accessibilityElement(children: .combine)
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
    var answering = false
    /// An option ID, or nil to explicitly dismiss. Never arbitrary card text.
    var answer: ((String?) -> Void)? = nil
    /// Puts a card's reply in the composer.
    let reply: (String) -> Void

    var body: some View {
        if let decision = message.decision {
            VStack(alignment: .leading, spacing: 12) {
                if decision.status == "pending", let card = message.ui {
                    CardView(card: card, fallback: message.content, decision: decision, answer: answer, reply: reply)
                        .allowsHitTesting(!answering)
                } else {
                    DecisionContent(decision: decision, answer: answer)
                        .disabled(answering || answer == nil)
                }
                if decision.status == "pending" {
                    if decision.allow_other {
                        Text("You can also type your answer in the composer.")
                            .font(.caption).foregroundStyle(Noora.labelSecondary)
                    }
                    HStack {
                        Button("Dismiss") { answer?(nil) }
                            .disabled(answering || answer == nil)
                        if answering { ProgressView().controlSize(.small) }
                    }
                }
            }
        } else if let card = message.ui {
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
                    if let files = message.attachments, !files.isEmpty {
                        MessageAttachments(files: files)
                    }
                    if !message.content.isEmpty {
                        Text(verbatim: message.content)
                            .textSelection(.enabled)
                            .foregroundStyle(Noora.labelPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Noora.neutralHover, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noora.border, lineWidth: 1))
                    }
                }
                .accessibilityElement(children: message.attachments?.isEmpty == false ? .contain : .combine)
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
    let owner: LoungePerson?
    let participants: [LoungePerson]

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
