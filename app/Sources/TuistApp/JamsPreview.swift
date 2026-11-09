#if os(iOS)
    import SwiftUI
    import TuistAuthentication
    import TuistServer

    struct JamsPreview: View {
        let accountName: String
        let isLayoutPreview: Bool
        private let client: JamClient?

        init(accountName: String, isLayoutPreview: Bool = false) {
            self.accountName = accountName
            self.isLayoutPreview = isLayoutPreview
            client = isLayoutPreview ? nil : JamClient(account: accountName, serverURL: AppServerEnvironmentService().url())
        }

        private var isLive: Bool { client != nil }
        @State private var jams: [DemoJam] = []
        @State private var nextCursor: String?
        @State private var loading = false
        @State private var hasLoaded = false
        @State private var loadID = UUID()
        @State private var showingNewJam = false
        @State private var newGoal = ""
        @State private var newProfile = "linux"
        @State private var newRepository = ""
        @State private var newModel: JamModel?
        @State private var newRequestID = UUID()
        @State private var newRequestContent: [String] = []
        @State private var selectedJam: DemoJam?
        @State private var drafts: [String: JamConversationDraft] = [:]
        @State private var archivedIDs: Set<String> = []
        @State private var showingArchived = false
        @State private var error: String?
        @Environment(\.scenePhase) private var scenePhase

        var body: some View {
            NavigationStack {
                List {
                    Picker("Jams", selection: $showingArchived) {
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
                    if isLive, !hasLoaded, error == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    } else if visibleJams.isEmpty, !loading, error == nil, nextCursor == nil {
                        Section {
                            JamEmptyStateView(archived: showingArchived)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                    jamSection("In progress", values: visibleJams.filter(\.isRunning))
                    jamSection(
                        showingArchived ? "Archived" : "Recent",
                        values: visibleJams.filter { !$0.isRunning }
                    )
                    if nextCursor != nil {
                        Button("Load more jams") { Task { await load(more: true) } }
                            .disabled(loading)
                    }
                }
                .refreshable { await load() }
                .navigationTitle("Jams")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New jam", systemImage: "square.and.pencil") { showingNewJam = true }
                            .labelStyle(.iconOnly)
                    }
                }
                .navigationDestination(item: $selectedJam) { jam in
                    JamConversationView(
                        jam: jam, client: client,
                        draft: Binding(
                            get: { drafts[jam.id] ?? JamConversationDraft() },
                            set: { drafts[jam.id] = $0 }
                        ),
                        archived: isArchived(jam),
                        update: { value in
                            jams.removeAll { $0.id == value.id }
                            jams.insert(value, at: 0)
                        },
                        archive: { value in
                            if value { archivedIDs.insert(jam.id) } else { archivedIDs.remove(jam.id) }
                        }
                    )
                }
                .sheet(isPresented: $showingNewJam) {
                    NewJamPreview(
                        client: client, goal: $newGoal, profile: $newProfile, repository: $newRepository,
                        selectedModel: $newModel, requestID: $newRequestID, requestContent: $newRequestContent
                    ) { jam in
                        jams.insert(jam, at: 0)
                        newGoal = ""
                        newRepository = ""
                        newModel = nil
                        newRequestID = UUID()
                        newRequestContent = []
                        showingNewJam = false
                        selectedJam = jam
                    }
                }
                .task(id: "\(scenePhase)-\(selectedJam?.id ?? "inbox")") {
                    guard let client, scenePhase == .active, selectedJam == nil else { return }
                    await load()
                    await client.watch(invalidate: { await load(preserveLoaded: true) }, disconnected: {
                        if error == nil { error = String(localized: "Connection lost. Reconnecting…") }
                    })
                }
                .onDisappear { loadID = UUID() }
            }
        }

        private var visibleJams: [DemoJam] {
            if isLive { return jams.filter { isArchived($0) == showingArchived } }
            #if DEBUG
                let values = jams + JamPreviewFixtures.jams
                    .filter { fixture in !jams.contains { $0.id == fixture.id } }
                return values.filter { archivedIDs.contains($0.id) == showingArchived }
            #else
                return []
            #endif
        }

        private func isArchived(_ jam: DemoJam) -> Bool {
            isLive ? jam.archiveStatus == "archived" || jam.status == "archived" : archivedIDs.contains(jam.id)
        }

        @ViewBuilder
        private func jamSection(_ title: LocalizedStringKey, values: [DemoJam]) -> some View {
            if !values.isEmpty {
                Section(title) {
                    ForEach(values) { jam in
                        Button { selectedJam = jam } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: archivedIDs.contains(jam.id) ? "archivebox" : jam
                                    .isRunning ? "circle.dotted" : "bubble.left")
                                    .foregroundStyle(jam.isRunning ? Color.accentColor : .secondary)
                                    .frame(width: 20)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(verbatim: jam.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                                    Text(verbatim: "\(jam.repository) · \(statusLabel(jam.status))")
                                        .font(.caption).foregroundStyle(.secondary)
                                    if jam.visibility == "shared" {
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
                let preserving = preserveLoaded && !jams.isEmpty
                let cursor = more ? nextCursor : nil
                let page = try await client.jams(cursor: cursor)
                guard !Task.isCancelled, loadID == id else { return }
                if more {
                    jams += page.jams.filter { value in !jams.contains { $0.id == value.id } }
                } else if preserving {
                    let refreshed = JamPage(jams: jams, nextCursor: nextCursor).mergingRefresh(page)
                    jams = refreshed.jams
                    nextCursor = refreshed.nextCursor
                } else { jams = page.jams }
                if !preserving { nextCursor = page.nextCursor == cursor ? nil : page.nextCursor }
                hasLoaded = true
                error = nil
            } catch {
                guard !Task.isCancelled, loadID == id else { return }
                self.error = error.localizedDescription
            }
        }
    }

    private struct NewJamPreview: View {
        let client: JamClient?
        private var isLive: Bool { client != nil }
        @Environment(\.dismiss) private var dismiss
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Environment(\.scenePhase) private var scenePhase
        @Binding var goal: String
        @Binding var profile: String
        @Binding var repository: String
        @Binding var selectedModel: JamModel?
        @Binding var requestID: UUID
        @Binding var requestContent: [String]
        let created: (DemoJam) -> Void
        @State private var repositories: [JamRepository] = []
        @State private var models: [JamModel] = []
        @State private var modelErrors: [JamModelCatalog.ProviderError] = []
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
                    .accessibilityLabel("Close new jam")
                    Spacer(minLength: 8)
                    Text("New jam")
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
                        .accessibilityIdentifier("jam-goal")
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
                .accessibilityIdentifier("jam-model")

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
            .modifier(JamGlassSurface(cornerRadius: 32))
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
                    JamRepositoryPickerPreview(
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
                NewJamSettings(
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
                    .modifier(JamGlassSurface(cornerRadius: 22, interactive: true))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain).foregroundStyle(.primary)
            .accessibilityLabel("Repository")
            .accessibilityValue(repository)
            .accessibilityIdentifier("jam-repository")
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
                    .modifier(JamGlassSurface(cornerRadius: 22, interactive: !isLive))
            }
            .foregroundStyle(.primary)
            .disabled(isLive)
            .accessibilityLabel("Environment")
            .accessibilityValue(profile == "macos" ? "macOS" : "Linux")
            .accessibilityIdentifier("jam-environment")
        }

        private var settingsControl: some View {
            Button {
                composing = false
                showingSettings = true
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .modifier(JamGlassSurface(cornerRadius: 22, interactive: true))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel("Jam settings")
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
            .accessibilityLabel(LocalizedStringKey(isLive ? "Start jam" : "Create preview jam"))
            .accessibilityIdentifier("jam-start")
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
                let jam: DemoJam
                if let client {
                    jam = try await client.create(
                        content: goal, repository: selectedRepository,
                        provider: selectedModel.provider, model: selectedModel.id, requestID: requestID
                    )
                } else {
                    #if DEBUG
                        jam = DemoJam(
                            id: UUID().uuidString, title: "New jam", repository: repository, profile: profile,
                            status: "preview", visibility: "private",
                            messages: [.init(id: UUID().uuidString, role: "user", content: goal)], goal: goal,
                            provider: selectedModel.provider, model: selectedModel.id
                        )
                    #else
                        throw URLError(.userAuthenticationRequired)
                    #endif
                }
                guard lifecycle == fence, !Task.isCancelled else { return }
                created(jam)
            } catch {
                guard lifecycle == fence, !Task.isCancelled else { return }
                self.error = error.localizedDescription
                composing = true
            }
        }
    }

    extension NewJamPreview {
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
                                                Text(verbatim: JamModel(provider: issue.provider, id: "", name: "")
                                                    .providerName)
                                                Text(LocalizedStringKey(issue.code == "unsupported_subscription"
                                                        ? "This subscription is not supported for Jams."
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
                let catalog: JamModelCatalog
                if let client {
                    catalog = try await client.models()
                } else {
                    #if DEBUG
                        let arguments = ProcessInfo.processInfo.arguments
                        if arguments.contains("--jam-models-loading") {
                            try await Task.sleep(for: .seconds(3600))
                        }
                        if arguments.contains("--jam-models-error") { throw URLError(.notConnectedToInternet) }
                        let sample: String
                        if arguments.contains("--jam-models-empty") {
                            sample = #"{"models":[],"errors":[{"provider":"claude","code":"models_unavailable"}]}"#
                        } else if arguments.contains("--jam-models-partial") {
                            sample = #"{"models":[{"provider":"chatgpt","id":"sample-chatgpt","name":"Sample ChatGPT model"}],"errors":[{"provider":"claude","code":"unsupported_subscription"}]}"#
                        } else {
                            sample = #"{"models":[{"provider":"chatgpt","id":"sample-chatgpt","name":"Sample ChatGPT model"}],"errors":[]}"#
                        }
                        catalog = try JSONDecoder().decode(JamModelCatalog.self, from: Data(sample.utf8))
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

    private struct NewJamSettings: View {
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
                        Text("Each repository jam gets its own worktree and branch. The original checkout is not edited.")
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
                        Label("Private jam", systemImage: "lock")
                    } footer: {
                        Text(LocalizedStringKey(isLive ? "Private jams only" :
                                "Start privately. Inviting someone would share the existing conversation with them."))
                    }
                    Section {} footer: {
                        Text(LocalizedStringKey(isLive
                                ? "Shipping requires a separate review and explicit approval. Repository policy determines the target."
                                : "Design preview · Starting creates a sample jam, not a running environment."))
                    }
                }
                .navigationTitle("Jam settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingSettings = false } } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private struct JamRepositoryPickerPreview: View {
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
        private enum JamPreviewFixtures {
            static let jams: [DemoJam] = [
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
                    ], goal: "Investigate the flaky checkout test and prepare a fix.", branch: "jams/flaky-checkout"
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
                    ], goal: "@Tuist investigate what we need to support offline search.", branch: "jams/offline-search"
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
                                    "Illustrative evidence only. No tests were executed by this sample jam.",
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
                    """, goal: "Make cache misses easier to diagnose.", branch: "jams/cache-diagnostics"
                ),
            ]
        }
    #endif

#endif
