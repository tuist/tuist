import SwiftUI

struct AtlasCodingSettingsView: View {
    @StateObject private var model: AtlasCodingRepositories
    @State private var choosingRepository = false
    @Environment(\.atlasPresence) private var presence

    init(request: @escaping AtlasEnvironmentRequest) {
        _model = StateObject(wrappedValue: AtlasCodingRepositories(request: request))
    }

    var body: some View {
        Form {
            if let catalog = model.catalog {
                Section {
                    Picker("GitHub installation", selection: Binding(get: { model.draft.installationId ?? "" }, set: { id in
                        Task { await model.chooseInstallation(id.isEmpty ? nil : id) }
                    })) {
                        Text("None").tag("")
                        ForEach(catalog.installations) { Text($0.name).tag($0.id) }
                    }
                    .accessibilityIdentifier("coding-installation")
                    Button { choosingRepository = true } label: {
                        LabeledContent("Default repository", value: model.draft.defaultRepository ?? "None")
                    }
                    .disabled(model.draft.installationId == nil)
                    .accessibilityIdentifier("coding-default-repository")
                } footer: {
                    Text("Only repositories available to both you and the GitHub App are listed. " +
                         "The default applies to new private conversations on all your devices.")
                }
                .disabled(model.busy)
                Section {
                    Button("Save settings") { Task { await model.save() } }
                        .disabled(model.busy || !model.dirty)
                        .accessibilityIdentifier("coding-save")
                } footer: {
                    Text("Choosing a repository does not clone it or enable an execution environment. " +
                         "Existing conversations stay unchanged.")
                }
            }
            if let message = model.message {
                Section { Text(message).foregroundStyle(.secondary) }
            }
            Section {
                Button("Refresh GitHub repositories") {
                    Task { await model.load() }
                }.disabled(model.busy)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Coding")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .overlay { if model.busy { ProgressView("Loading repositories…") } }
        .sheet(isPresented: $choosingRepository) {
            AtlasRepositoryList(names: model.catalog?.repositories.map(\.fullName) ?? [],
                                selected: model.draft.defaultRepository, title: "Default repository") {
                model.chooseRepository($0)
            }
        }
        .onAppear { presence?.show() }
        .task { await model.load() }
        .onDisappear { model.stop() }
        .protectsAtlasNavigation(model.busy || model.dirty)
    }
}

struct AtlasRepositoryList: View {
    let names: [String]
    let selected: String?
    var title = "Repository"
    let choose: (String?) -> Void
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField("Find a repository", text: $search).textFieldStyle(.roundedBorder)
            repositories
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 360)
        #else
        NavigationStack {
            repositories
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a repository")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var repositories: some View {
        List {
            let matches = names.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }
            AtlasRepositoryChoice(name: nil, selected: selected) { choose(nil); dismiss() }
            ForEach(matches, id: \.self) { name in
                AtlasRepositoryChoice(name: name, selected: selected) { choose(name); dismiss() }
            }
            if !search.isEmpty && matches.isEmpty {
                Text("No repositories found").foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
    }
}

private struct AtlasRepositoryChoice: View {
    let name: String?
    let selected: String?
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack {
                Text(name ?? "No repository").foregroundStyle(.primary)
                Spacer()
                if name == selected { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true) }
            }
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(name == selected ? "Selected" : "Not selected")
    }
}

struct AtlasThreadRepositoryPicker: View {
    let threadId: String
    let selected: String?
    let request: AtlasEnvironmentRequest
    let changed: () async -> Void
    @State private var catalog: AtlasRepositoryCatalog?
    @State private var search = ""
    @State private var busy = false
    @State private var message: String?
    @State private var generation = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            #if os(macOS)
            VStack(alignment: .leading, spacing: 12) {
                Text("Repository").font(.headline)
                TextField("Find a repository", text: $search).textFieldStyle(.roundedBorder)
                repositories
                actions
                Divider()
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                }
            }
            .padding(20)
            #else
            repositories
                .safeAreaInset(edge: .bottom) {
                    actions.padding().background(.bar)
                }
                .navigationTitle("Repository")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a repository")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            #endif
        }
        .disabled(busy)
        .overlay { if busy { ProgressView() } }
        .task { await load() }
        .interactiveDismissDisabled(busy)
        .onDisappear { generation += 1; busy = false }
        #if os(macOS)
        .frame(width: 480, height: 400)
        #endif
    }

    private var repositories: some View {
        List {
            let matches = catalog?.repositories.filter { search.isEmpty || $0.fullName.localizedCaseInsensitiveContains(search) } ?? []
            Section {
                AtlasRepositoryChoice(name: nil, selected: selected) { Task { await choose(nil) } }
                ForEach(matches) { repository in
                    AtlasRepositoryChoice(name: repository.fullName, selected: selected) { Task { await choose(repository.fullName) } }
                }
                if !search.isEmpty && matches.isEmpty {
                    Text("No repositories found").foregroundStyle(.secondary)
                }
            } footer: {
                Text("Switching repositories clears the tool environment.").font(.caption).fontWeight(.regular)
            }
            if let message { Text(message).foregroundStyle(.secondary) }
            if catalog?.repositories.isEmpty == true && search.isEmpty {
                Text("Choose a GitHub installation in Coding settings.").foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
    }

    private var actions: some View {
        HStack {
            NavigationLink("Coding settings…") { AtlasCodingSettingsView(request: request) }
            Spacer()
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await load() } }
        }
        .buttonStyle(.borderless)
    }

    private func load() async {
        guard !busy else { return }
        let current = generation
        busy = true
        defer { if current == generation { busy = false } }
        do {
            let data = try await request(["action": "repositories"])
            try Task.checkCancellation()
            guard current == generation else { return }
            catalog = try AtlasEnvironmentCoding.decode(AtlasRepositoryCatalog.self, from: data)
            message = nil
        } catch { if current == generation, !Task.isCancelled { catalog = nil; message = error.localizedDescription } }
    }

    private func choose(_ repository: String?) async {
        guard !busy else { return }
        if repository == selected { dismiss(); return }
        let current = generation
        busy = true
        defer { if current == generation { busy = false } }
        do {
            let data = try await request(["action": "select", "thread_id": threadId, "environment_id": NSNull(),
                                          "project_id": NSNull(), "repository": repository as Any? ?? NSNull()])
            let result = try AtlasEnvironmentCoding.decode(AtlasEnvironmentSelection.self, from: data)
            try Task.checkCancellation()
            guard current == generation else { return }
            guard result.thread.id == threadId else { throw CocoaError(.coderInvalidValue) }
            await changed()
            dismiss()
        } catch { if current == generation, !Task.isCancelled { message = error.localizedDescription } }
    }
}
