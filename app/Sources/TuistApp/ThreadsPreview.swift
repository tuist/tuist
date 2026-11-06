#if os(iOS)
    import SwiftUI
    import TuistAuthentication
    import TuistServer

    struct ThreadsPreview: View {
        let accountName: String
        var isLayoutPreview = false
        let switchAccount: () -> Void
        private var client: ThreadClient? {
            #if DEBUG
                if isLayoutPreview { return nil }
            #endif
            return ThreadClient(account: accountName, serverURL: AppServerEnvironmentService().url())
        }

        private var isLive: Bool { client != nil }
        @State private var sessions: [DemoThread] = []
        @State private var nextCursor: String?
        @State private var loading = false
        @State private var loadID = UUID()
        @State private var showingNewSession = false
        @State private var newGoal = ""
        @State private var newProfile = "linux"
        @State private var newRepository = ""
        @State private var newModel: ThreadModel?
        @State private var newRequestID = UUID()
        @State private var newRequestContent: [String] = []
        @State private var selectedSession: DemoThread?
        @State private var drafts: [String: ThreadConversationDraft] = [:]
        @State private var archivedIDs: Set<String> = []
        @State private var showingArchived = false
        @State private var error: String?
        @Environment(\.scenePhase) private var scenePhase

        var body: some View {
            NavigationStack {
                List {
                    Picker("Threads", selection: $showingArchived) {
                        Text("Active").tag(false)
                        Text("Archived").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    if let error {
                        Section {
                            Text(error).foregroundStyle(.secondary)
                            Button("Try again") { Task { await load() } }
                        }
                    }
                    if isLive, sessions.isEmpty, error == nil {
                        Section {
                            ContentUnavailableView(
                                "Start with a goal", systemImage: "square.and.pencil",
                                description: Text("Ask Tuist a question or choose a repository to work on.")
                            )
                        }
                    }
                    sessionSection("In progress", values: visibleSessions.filter(\.isRunning))
                    sessionSection(
                        showingArchived ? "Archived" : "Recent",
                        values: visibleSessions.filter { !$0.isRunning }
                    )
                    if nextCursor != nil {
                        Button("Load more threads") { Task { await load(more: true) } }
                            .disabled(loading)
                    }
                    Section {} footer: {
                        Text(LocalizedStringKey(isLive
                                ? "Private · Threads are saved to your account"
                                : "Design preview · Sample threads and people"))
                    }
                }
                .refreshable { await load() }
                .navigationTitle("Threads")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: switchAccount) {
                            HStack(spacing: 4) {
                                Text(verbatim: accountName)
                                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                            }
                        }
                        .tint(.primary)
                        .accessibilityLabel("Switch account")
                        .accessibilityValue(accountName)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New thread", systemImage: "square.and.pencil") { showingNewSession = true }
                            .labelStyle(.iconOnly)
                    }
                }
                .navigationDestination(item: $selectedSession) { session in
                    ThreadConversationView(
                        session: session, client: client,
                        draft: Binding(
                            get: { drafts[session.id] ?? ThreadConversationDraft() },
                            set: { drafts[session.id] = $0 }
                        ),
                        archived: isArchived(session),
                        update: { value in
                            sessions.removeAll { $0.id == value.id }
                            sessions.insert(value, at: 0)
                        },
                        archive: { value in
                            if value { archivedIDs.insert(session.id) } else { archivedIDs.remove(session.id) }
                        }
                    )
                }
                .sheet(isPresented: $showingNewSession) {
                    NewThreadPreview(
                        client: client, goal: $newGoal, profile: $newProfile, repository: $newRepository,
                        selectedModel: $newModel, requestID: $newRequestID, requestContent: $newRequestContent
                    ) { session in
                        sessions.insert(session, at: 0)
                        newGoal = ""
                        newRepository = ""
                        newModel = nil
                        newRequestID = UUID()
                        newRequestContent = []
                        showingNewSession = false
                        selectedSession = session
                    }
                }
                .task(id: "\(scenePhase)-\(selectedSession?.id ?? "inbox")") {
                    guard let client, scenePhase == .active, selectedSession == nil else { return }
                    await load()
                    await client.watch(invalidate: { await load(preserveLoaded: true) }, disconnected: {
                        error = String(localized: "Connection lost. Reconnecting…")
                    })
                }
                .onDisappear { loadID = UUID() }
            }
        }

        private var visibleSessions: [DemoThread] {
            if isLive { return sessions.filter { isArchived($0) == showingArchived } }
            #if DEBUG
                let values = sessions + ThreadPreviewFixtures.threads
                    .filter { fixture in !sessions.contains { $0.id == fixture.id } }
                return values.filter { archivedIDs.contains($0.id) == showingArchived }
            #else
                return []
            #endif
        }

        private func isArchived(_ session: DemoThread) -> Bool {
            isLive ? session.archiveStatus == "archived" || session.status == "archived" : archivedIDs.contains(session.id)
        }

        @ViewBuilder
        private func sessionSection(_ title: LocalizedStringKey, values: [DemoThread]) -> some View {
            if !values.isEmpty {
                Section(title) {
                    ForEach(values) { session in
                        Button { selectedSession = session } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: archivedIDs.contains(session.id) ? "archivebox" : session
                                    .isRunning ? "circle.dotted" : "bubble.left")
                                    .foregroundStyle(session.isRunning ? Color.accentColor : .secondary)
                                    .frame(width: 20)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(verbatim: session.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                                    Text(verbatim: "\(session.repository) · \(statusLabel(session.status))")
                                        .font(.caption).foregroundStyle(.secondary)
                                    if session.visibility == "shared" {
                                        Label("Shared with 2 people", systemImage: "person.2")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        private func load(more: Bool = false, preserveLoaded: Bool = false) async {
            guard let client else { return }
            if more, loading { return }
            let id = UUID()
            loadID = id
            loading = true
            defer { if loadID == id { loading = false } }
            do {
                let preserving = preserveLoaded && !sessions.isEmpty
                let cursor = more ? nextCursor : nil
                let page = try await client.threads(cursor: cursor)
                guard !Task.isCancelled, loadID == id else { return }
                if more {
                    sessions += page.threads.filter { value in !sessions.contains { $0.id == value.id } }
                } else if preserving {
                    let incoming = Set(page.threads.map(\.id))
                    sessions = page.threads + sessions.filter { !incoming.contains($0.id) }
                } else { sessions = page.threads }
                if !preserving { nextCursor = page.nextCursor == cursor ? nil : page.nextCursor }
                error = nil
            } catch {
                guard !Task.isCancelled, loadID == id else { return }
                self.error = error.localizedDescription
            }
        }
    }

    private struct NewThreadPreview: View {
        let client: ThreadClient?
        private var isLive: Bool { client != nil }
        @Environment(\.dismiss) private var dismiss
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Environment(\.scenePhase) private var scenePhase
        @Binding var goal: String
        @Binding var profile: String
        @Binding var repository: String
        @Binding var selectedModel: ThreadModel?
        @Binding var requestID: UUID
        @Binding var requestContent: [String]
        let created: (DemoThread) -> Void
        @State private var repositories: [ThreadRepository] = []
        @State private var models: [ThreadModel] = []
        @State private var modelErrors: [ThreadModelCatalog.ProviderError] = []
        @State private var modelLoadFailed = false
        @State private var loadingModels = true
        @State private var catalogID = UUID()
        @State private var lifecycle = UUID()
        @State private var busy = false
        @State private var error: String?
        @State private var showingRepositories = false
        @State private var showingSettings = false
        @State private var showingModels = false
        @FocusState private var composing: Bool

        var body: some View {
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        if dynamicTypeSize.isAccessibilitySize {
                            Image(systemName: "xmark").font(.system(size: 20))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        } else {
                            Label("Close", systemImage: "xmark")
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                    }
                    .accessibilityLabel("Close new thread")
                    Spacer(minLength: 8)
                    Text("New thread")
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 8)

                ZStack(alignment: .topLeading) {
                    if goal.isEmpty {
                        Text("What would you like Tuist to do?")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $goal)
                        .scrollContentBackground(.hidden)
                        .focused($composing)
                        .accessibilityLabel("Prompt")
                        .accessibilityIdentifier("thread-goal")
                }
                .font(.body)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Button {
                    composing = false
                    showingModels = true
                } label: {
                    HStack {
                        Label("Model", systemImage: "sparkles")
                        Spacer()
                        if loadingModels {
                            ProgressView().accessibilityLabel("Loading models…")
                        } else if let selectedModel, models.contains(selectedModel) {
                            Text(verbatim: "\(selectedModel.providerName) · \(selectedModel.name)")
                                .lineLimit(1)
                        } else {
                            Text("Choose model")
                        }
                        Image(systemName: "chevron.up.chevron.down").font(.caption)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 20).frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("thread-model")

                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20).padding(.bottom, 8)
                }
                Label(
                    LocalizedStringKey(isLive ? "Private · Saved to your account" :
                        "Private · Design preview · No work runs"),
                    systemImage: "lock"
                )
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.vertical, 8)
                Divider().opacity(0.4)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        repositoryControl
                        environmentControl
                        settingsControl
                        Spacer(minLength: 0)
                        startControl
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        repositoryControl
                        HStack(spacing: 8) {
                            environmentControl
                            settingsControl
                            Spacer(minLength: 0)
                            startControl
                        }
                    }
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(ThreadGlassSurface(cornerRadius: 32))
            .padding(8)
            .disabled(busy)
            .interactiveDismissDisabled(busy)
            .presentationBackground(.clear)
            .presentationDragIndicator(.hidden)
            .task(id: scenePhase) {
                guard scenePhase == .active else {
                    catalogID = UUID()
                    loadingModels = true
                    return
                }
                await loadModels()
            }
            .task {
                composing = true
                guard let client else { return }
                do {
                    let values = try await client.repositories()
                    guard !Task.isCancelled else { return }
                    repositories = values
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
            .onDisappear { lifecycle = UUID(); catalogID = UUID() }
            .sheet(isPresented: $showingModels, onDismiss: { composing = true }, content: {
                modelPicker
            })
            .sheet(isPresented: $showingRepositories, onDismiss: { composing = true }, content: {
                NavigationStack {
                    ThreadRepositoryPickerPreview(
                        repository: $repository,
                        repositories: repositories.map(\.fullName),
                        isLive: isLive
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showingRepositories = false }
                        }
                    }
                }
            })
            .sheet(isPresented: $showingSettings, onDismiss: { composing = true }, content: {
                NewThreadSettings(
                    repository: repository,
                    baseBranch: repositories.first { $0.fullName == repository }?.defaultBranch,
                    profile: profile,
                    isLive: isLive,
                    showingSettings: $showingSettings
                )
            })
        }

        private var repositoryControl: some View {
            Button {
                composing = false
                showingRepositories = true
            } label: {
                Label(repository.isEmpty ? String(localized: "No repository") : repository, systemImage: "folder")
                    .lineLimit(1)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .modifier(ThreadGlassSurface(cornerRadius: 22, interactive: true))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain).foregroundStyle(.primary)
            .accessibilityLabel("Repository")
            .accessibilityValue(repository)
            .accessibilityIdentifier("thread-repository")
        }

        private var environmentControl: some View {
            Menu {
                Picker("Environment", selection: $profile) {
                    if !isLive { Text("macOS").tag("macos") }
                    Text("Linux").tag("linux")
                }
            } label: {
                Text(profile == "macos" ? "macOS" : "Linux")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .modifier(ThreadGlassSurface(cornerRadius: 22, interactive: !isLive))
            }
            .foregroundStyle(.primary)
            .disabled(isLive)
            .accessibilityLabel("Environment")
            .accessibilityValue(profile == "macos" ? "macOS" : "Linux")
            .accessibilityIdentifier("thread-environment")
        }

        private var settingsControl: some View {
            Button {
                composing = false
                showingSettings = true
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .modifier(ThreadGlassSurface(cornerRadius: 22, interactive: true))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel("Thread settings")
        }

        private var startControl: some View {
            let ready = !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy
                && !loadingModels && selectedModel.map { models.contains($0) } == true
                && (!isLive || repository.isEmpty || repositories.contains { $0.fullName == repository })
            return Button {
                composing = false
                Task { await start() }
            } label: {
                Group {
                    if busy { ProgressView() } else { Image(systemName: "arrow.up").font(.system(size: 22, weight: .semibold)) }
                }
                .frame(width: 48, height: 48)
                .foregroundStyle(ready ? Color.white : .secondary)
                .background(ready ? Color.accentColor : Color.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!ready)
            .accessibilityLabel(LocalizedStringKey(isLive ? "Start thread" : "Create preview thread"))
            .accessibilityIdentifier("thread-start")
        }

        private func start() async {
            guard !loadingModels, let selectedModel, models.contains(selectedModel) else { return }
            let selectedRepository = repositories.first { $0.fullName == repository }
            guard !isLive || repository.isEmpty || selectedRepository != nil else { return }
            busy = true
            defer { busy = false }
            let fence = lifecycle
            let content = [goal, repository, selectedRepository?.defaultBranch ?? "", selectedModel.provider, selectedModel.id]
            if requestContent != content {
                requestID = UUID()
                requestContent = content
            }
            do {
                let session: DemoThread
                if let client {
                    session = try await client.create(
                        content: goal, repository: selectedRepository,
                        provider: selectedModel.provider, model: selectedModel.id, requestID: requestID
                    )
                } else {
                    #if DEBUG
                        session = DemoThread(
                            id: UUID().uuidString, title: "New thread", repository: repository, profile: profile,
                            status: "preview", visibility: "private",
                            messages: [.init(id: UUID().uuidString, role: "user", content: goal)], goal: goal,
                            provider: selectedModel.provider, model: selectedModel.id
                        )
                    #else
                        throw URLError(.userAuthenticationRequired)
                    #endif
                }
                guard lifecycle == fence, !Task.isCancelled else { return }
                created(session)
            } catch {
                guard lifecycle == fence, !Task.isCancelled else { return }
                self.error = error.localizedDescription
                composing = true
            }
        }
    }

    extension NewThreadPreview {
        fileprivate var modelPicker: some View {
            NavigationStack {
                Group {
                    if modelLoadFailed, !loadingModels {
                        ContentUnavailableView {
                            Label("Couldn’t load models", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text("Check your connection or try again in a moment.")
                        } actions: {
                            Button("Try again") { Task { await loadModels() } }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                        }
                    } else {
                        List {
                            if loadingModels {
                                ProgressView("Loading models…")
                            } else {
                                if models.isEmpty {
                                    ContentUnavailableView(
                                        "No models available", systemImage: "sparkles",
                                        description: Text("Connect an AI subscription in your profile, then try again.")
                                    )
                                }
                                ForEach(["chatgpt", "claude"], id: \.self) { provider in
                                    let values = models.filter { $0.provider == provider }
                                    if !values.isEmpty {
                                        Section(provider == "chatgpt" ? "ChatGPT" : "Claude") {
                                            ForEach(values, id: \.self) { model in
                                                Button {
                                                    selectedModel = model
                                                    showingModels = false
                                                } label: {
                                                    HStack {
                                                        Text(verbatim: model.name).foregroundStyle(.primary)
                                                        Spacer()
                                                        if selectedModel == model { Image(systemName: "checkmark") }
                                                    }.frame(minHeight: 44)
                                                }
                                            }
                                        }
                                    }
                                }
                                if !modelErrors.isEmpty {
                                    Section {
                                        ForEach(modelErrors, id: \.self) { issue in
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(verbatim: ThreadModel(provider: issue.provider, id: "", name: "")
                                                    .providerName)
                                                Text(LocalizedStringKey(issue.code == "unsupported_subscription"
                                                        ? "This subscription is not supported for Threads."
                                                        : "Models unavailable. Try again later."))
                                                    .font(.footnote).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                                Button("Refresh models") { Task { await loadModels() } }
                            }
                            Section {} footer: {
                                Text(LocalizedStringKey(isLive
                                        ? "Models available through your profile’s AI subscriptions. The model cannot be changed after creation."
                                        : "Sample model catalog · Design preview · No subscription access implied"))
                            }
                        }
                    }
                }
                .navigationTitle("Choose model").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingModels = false } } }
            }
        }

        fileprivate func loadModels() async {
            let id = UUID()
            catalogID = id
            loadingModels = true
            models = []
            modelErrors = []
            modelLoadFailed = false
            do {
                let catalog: ThreadModelCatalog
                if let client {
                    catalog = try await client.models()
                } else {
                    #if DEBUG
                        let arguments = ProcessInfo.processInfo.arguments
                        if arguments.contains("--thread-models-loading") {
                            try await Task.sleep(for: .seconds(3600))
                        }
                        if arguments.contains("--thread-models-error") { throw URLError(.notConnectedToInternet) }
                        let sample: String
                        if arguments.contains("--thread-models-empty") {
                            sample = #"{"models":[],"errors":[{"provider":"claude","code":"models_unavailable"}]}"#
                        } else if arguments.contains("--thread-models-partial") {
                            sample = #"{"models":[{"provider":"chatgpt","id":"sample-chatgpt","name":"Sample ChatGPT model"}],"errors":[{"provider":"claude","code":"unsupported_subscription"}]}"#
                        } else {
                            sample = #"{"models":[{"provider":"chatgpt","id":"sample-chatgpt","name":"Sample ChatGPT model"}],"errors":[]}"#
                        }
                        catalog = try JSONDecoder().decode(ThreadModelCatalog.self, from: Data(sample.utf8))
                    #else
                        throw URLError(.userAuthenticationRequired)
                    #endif
                }
                guard catalogID == id, !Task.isCancelled else { return }
                models = catalog.models.filter { ["chatgpt", "claude"].contains($0.provider) && !$0.id.isEmpty }
                modelErrors = catalog.errors
                if let selectedModel, !models.contains(selectedModel) { self.selectedModel = nil }
                loadingModels = false
            } catch {
                guard catalogID == id, !Task.isCancelled else { return }
                modelLoadFailed = true
                loadingModels = false
            }
        }
    }

    private struct NewThreadSettings: View {
        let repository: String
        let baseBranch: String?
        let profile: String
        let isLive: Bool
        @Binding var showingSettings: Bool

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        LabeledContent("Repository", value: repository.isEmpty ? String(localized: "No repository") : repository)
                        if let baseBranch {
                            LabeledContent("Base branch", value: baseBranch)
                        }
                    } footer: {
                        Text("Each repository thread gets its own worktree and branch. The original checkout is not edited.")
                    }
                    Section("Tool environment") {
                        LabeledContent("Provider", value: "Tuist")
                        LabeledContent("Profile", value: profile == "macos" ? "macOS" : "Linux")
                        if !isLive {
                            LabeledContent("Resources", value: profile == "macos" ? "6 vCPU · 14 GB" : "2 vCPU · 8 GB")
                            if profile == "macos" { LabeledContent("Xcode", value: "26.5") }
                        }
                    }
                    Section {
                        Label("Private thread", systemImage: "lock")
                    } footer: {
                        Text(LocalizedStringKey(isLive ? "Private threads only" :
                                "Start privately. Inviting someone would share the existing conversation with them."))
                    }
                    Section {} footer: {
                        Text(LocalizedStringKey(isLive
                                ? "Shipping requires a separate review and explicit approval. Repository policy determines the target."
                                : "Design preview · Starting creates a sample thread, not a running environment."))
                    }
                }
                .navigationTitle("Thread settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingSettings = false } } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private struct ThreadRepositoryPickerPreview: View {
        @Binding var repository: String
        let repositories: [String]
        let isLive: Bool
        @State private var search = ""
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            List {
                Section {
                    Button("No repository") { repository = ""; dismiss() }
                    ForEach((isLive ? repositories : ["tuist/tuist", "tuist/noora", "tuist/app"]).filter {
                        search.isEmpty || $0.localizedCaseInsensitiveContains(search)
                    }, id: \.self) { name in
                        Button {
                            repository = name
                            dismiss()
                        } label: {
                            HStack {
                                Text(name).foregroundStyle(.primary)
                                Spacer()
                                if repository == name { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } header: {
                    Text("Repositories")
                } footer: {
                    Text(LocalizedStringKey(isLive ? "Repositories available to this account." :
                            "Sample repositories · Design preview"))
                }
            }
            .searchable(text: $search, prompt: "Search repositories")
            .navigationTitle("Repositories")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "queued": String(localized: "Queued")
        case "running": String(localized: "Running")
        case "completed": String(localized: "Ready to review")
        case "failed": String(localized: "Needs attention")
        case "outcome_unknown": String(localized: "Outcome unknown")
        default: String(localized: "Preview")
        }
    }

    #if DEBUG
        private enum ThreadPreviewFixtures {
            static let threads: [DemoThread] = [
                .init(
                    id: "private-preview", title: "Fix flaky checkout test", repository: "tuist/tuist", profile: "macos",
                    status: "running", visibility: "private", messages: [
                        .init(id: "goal", role: "user", content: "Investigate the flaky checkout test and prepare a fix."),
                        .init(
                            id: "reply",
                            role: "assistant",
                            content: "I’ll inspect the failing test, reproduce the failure, then verify a focused fix."
                        ),
                        .init(
                            id: "tool",
                            role: "tool",
                            content: "Read checkout tests\nSample tool evidence from a macOS environment."
                        ),
                    ], goal: "Investigate the flaky checkout test and prepare a fix.", branch: "threads/flaky-checkout"
                ),
                .init(
                    id: "shared-preview", title: "Add offline search", repository: "tuist/app", profile: "linux",
                    status: "preview", visibility: "shared", messages: [
                        .init(id: "goal", role: "user", content: "@Tuist investigate what we need to support offline search."),
                        .init(
                            id: "reply",
                            role: "assistant",
                            content: "I found two options. Should the first version search cached projects only, or cached previews too?"
                        ),
                        .init(id: "person", role: "Marek", content: "Let’s keep it scoped to cached projects first."),
                    ], goal: "@Tuist investigate what we need to support offline search.", branch: "threads/offline-search"
                ),
                .init(
                    id: "review-preview", title: "Improve cache diagnostics", repository: "tuist/tuist", profile: "linux",
                    status: "completed", visibility: "private", messages: [
                        .init(id: "goal", role: "user", content: "Make cache misses easier to diagnose."),
                        .init(
                            id: "read",
                            role: "tool",
                            content: "Found the cache miss reporting path.",
                            toolName: "Read cache diagnostics",
                            toolStatus: "Completed",
                            toolInput: "CacheDiagnostics.swift"
                        ),
                        .init(
                            id: "edit",
                            role: "tool",
                            content: "Added the target name and miss reason.",
                            toolName: "Edit diagnostics",
                            toolStatus: "Completed"
                        ),
                        .init(
                            id: "tests",
                            role: "tool",
                            content: "Sample result: 12 tests passed, 0 failures.",
                            toolName: "Run focused tests",
                            toolStatus: "Completed",
                            toolInput: "swift test --filter CacheDiagnosticsTests",
                            richContent: .init(
                                kind: "test_results", title: "12 tests passed",
                                summary: "Focused coverage for cache-miss diagnostics.",
                                facts: [
                                    .init(label: "Failures", value: "0"),
                                    .init(label: "Suite", value: "CacheDiagnosticsTests"),
                                ],
                                details: [
                                    "Target name and miss reason appear in the diagnostic.",
                                    "An unchanged target still reports a cache hit.",
                                    "Illustrative evidence only. No tests were executed by this sample thread.",
                                ]
                            )
                        ),
                        .init(
                            id: "reply",
                            role: "assistant",
                            content: """
                            The change is ready to review.

                            - Cache misses now include the **target** and **reason**.
                            - The focused diagnostics tests pass.

                            ```text
                            App · cache miss
                            Reason: source files changed
                            ```

                            This is a sample result, not an executed change. Review the illustrative diff before shipping.
                            """,
                            suggestions: ["Review the diff", "Explain the tests"],
                            richContent: .init(
                                kind: "change_summary", title: "Ready for review",
                                summary: "Cache misses now explain which target changed and why.",
                                facts: [
                                    .init(label: "Changed file", value: "CacheDiagnostics.swift"),
                                    .init(label: "Verification", value: "12 passed · 0 failed"),
                                ],
                                details: [
                                    "Before: Cache miss",
                                    "After: App · cache miss: source files changed",
                                    "This is a sample change. Ship requires repository policy and explicit approval on a live account.",
                                ]
                            )
                        ),
                    ], diff: """
                    --- a/CacheDiagnostics.swift
                    +++ b/CacheDiagnostics.swift
                    @@ -1 +1 @@
                    -logger.info("Cache miss")
                    +logger.info("\\(target.name) · cache miss: \\(reason)")
                    """, goal: "Make cache misses easier to diagnose.", branch: "threads/cache-diagnostics"
                ),
            ]
        }
    #endif

#endif
