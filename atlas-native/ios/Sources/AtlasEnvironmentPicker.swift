import SwiftUI

private struct AtlasEnvironmentRequestKey: EnvironmentKey {
    static let defaultValue: AtlasEnvironmentRequest? = nil
}

extension EnvironmentValues {
    var atlasEnvironmentRequest: AtlasEnvironmentRequest? {
        get { self[AtlasEnvironmentRequestKey.self] }
        set { self[AtlasEnvironmentRequestKey.self] = newValue }
    }
}

struct AtlasEnvironmentPicker: View {
    let threadId: String
    let request: AtlasEnvironmentRequest
    @State private var overview: AtlasEnvironmentOverview?
    @State private var selection: AtlasEnvironmentSelection.Thread?
    @State private var busy = false
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        control
        .task(id: threadId) { await load() }
        .task(id: scenePhase == .active && transitioning) {
            while !Task.isCancelled && scenePhase == .active && transitioning {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if !Task.isCancelled { await load() }
                if message != nil { break }
            }
        }
    }

    private var transitioning: Bool {
        overview?.environments.contains(where: { ["starting", "stopping"].contains($0.providerState ?? "") }) == true
    }

    #if os(macOS)
    private enum Choice: Hashable {
        case server
        case provider(String)
        case project(String, String)
    }

    private var selectedChoice: Choice {
        guard let id = selection?.environmentId,
              let environment = overview?.environments.first(where: { $0.id == id }) else { return .server }
        if !environment.native, let provider = environment.provider { return .provider(provider) }
        return selection?.projectId.map { .project(id, $0) } ?? .server
    }

    private var control: some View {
        Menu {
            Picker("Tool environment", selection: Binding(get: { selectedChoice }, set: { value in
                Task {
                    switch value {
                    case .server: await choose(environment: nil, project: nil)
                    case .provider(let id): await start(provider: id)
                    case .project(let environment, let project): await choose(environment: environment, project: project)
                    }
                }
            })) {
                Text("Atlas server").tag(Choice.server)
                if let providers = overview?.providers, !providers.isEmpty {
                    Section("Hosted environments") {
                        ForEach(providers) { provider in
                            let state = overview?.environments.first(where: {
                                $0.id == selection?.environmentId && $0.provider == provider.id
                            })?.providerState
                            Text(provider.name + (state.map { " · " + $0.capitalized } ?? ""))
                                .tag(Choice.provider(provider.id))
                        }
                    }
                }
                ForEach(overview?.environments.filter { $0.enabled && $0.native } ?? []) { environment in
                    Section(environment.name + (environment.online ? "" : " · Offline")) {
                        ForEach(environment.projects) { project in
                            Text(project.name).tag(Choice.project(environment.id, project.id))
                        }
                    }
                }
            }
            .pickerStyle(.inline)
            .disabled(busy || selection == nil)
            if busy { Text("Updating environments…") }
            if message != nil {
                Divider()
                Button("Try again") { Task { await load() } }
            }
        } label: {
            Label("Tool environment", systemImage: "desktopcomputer")
        }
        .help(message ?? "Choose where Pip’s file and terminal tools run. Switching away pauses a hosted workspace.")
        .accessibilityIdentifier("thread-environment")
    }
    #else
    private var control: some View {
        Form {
            Section {
                choice("Atlas server", environment: nil, project: nil)
            } footer: {
                Text("Pip always runs on Atlas. Choose where its file and terminal tools run.")
            }
            if let providers = overview?.providers, !providers.isEmpty {
                Section {
                    ForEach(providers) { provider in
                        Button {
                            Task { await start(provider: provider.id) }
                        } label: {
                            HStack {
                                Text(provider.name)
                                Spacer()
                                if let environment = overview?.environments.first(where: {
                                    $0.id == selection?.environmentId && $0.provider == provider.id
                                }) {
                                    Text(environment.providerState?.capitalized ?? "Selected").foregroundStyle(.secondary)
                                    Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true)
                                }
                            }.frame(minHeight: 44)
                        }.buttonStyle(.plain).disabled(busy || selection == nil)
                    }
                } header: {
                    Text("Hosted environments")
                } footer: {
                    Text("Starts a Linux workspace with file and terminal access. Selecting Atlas server stops it. " +
                         "Files may expire after inactivity; repository credentials are not shared.")
                }
            }
            ForEach(overview?.environments.filter { $0.enabled && $0.native } ?? []) { environment in
                Section {
                    ForEach(environment.projects) { project in
                        choice(project.name, environment: environment.id, project: project.id)
                    }
                    if environment.projects.isEmpty {
                        Text("No projects available in this environment.").foregroundStyle(.secondary)
                    }
                } header: {
                    Text(environment.name + (environment.online ? "" : " · Offline"))
                } footer: {
                    Text("Files and commands run in this environment. Atlas keeps the conversation and AI session.")
                }
            }
            if overview?.environments.contains(where: { $0.enabled && $0.native }) == false {
                Section {
                    Text("To use files and terminal tools on your Mac, enable This Mac in Atlas for macOS Settings.")
                        .foregroundStyle(.secondary)
                }
            }
            if let message {
                Section {
                    Text(message).foregroundStyle(.secondary)
                    Button("Try again") { Task { await load() } }.disabled(busy)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Tool environment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .overlay { if busy { ProgressView().accessibilityLabel("Updating environment") } }
    }

    private func choice(_ name: String, environment: String?, project: String?) -> some View {
        let selected = selection != nil && selection?.environmentId == environment && selection?.projectId == project
        return Button {
            Task { await choose(environment: environment, project: project) }
        } label: {
            HStack {
                Text(name)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(busy || selection == nil)
            .accessibilityValue(selected ? "Selected" : "Not selected")
    }
    #endif

    private func load() async {
        busy = true
        defer { if !Task.isCancelled { busy = false } }
        do {
            async let list = request(["action": "list"])
            async let current = request(["action": "selection", "thread_id": threadId])
            let available = try AtlasEnvironmentCoding.decode(AtlasEnvironmentOverview.self, from: await list)
            let selected = try AtlasEnvironmentCoding.decode(AtlasEnvironmentSelection.self, from: await current)
            try Task.checkCancellation()
            guard selected.thread.id == threadId else { throw CocoaError(.coderInvalidValue) }
            overview = available
            selection = selected.thread
            message = nil
        } catch { if !Task.isCancelled { message = error.localizedDescription } }
    }

    private func choose(environment: String?, project: String?) async {
        busy = true
        defer { busy = false }
        do {
            let data = try await request([
                "action": "select", "thread_id": threadId, "environment_id": environment as Any? ?? NSNull(),
                "project_id": project as Any? ?? NSNull()
            ])
            let selected = try AtlasEnvironmentCoding.decode(AtlasEnvironmentSelection.self, from: data)
            try Task.checkCancellation()
            guard selected.thread.id == threadId else { throw CocoaError(.coderInvalidValue) }
            selection = selected.thread
            message = nil
            await load()
        } catch { message = error.localizedDescription }
    }

    private func start(provider: String) async {
        busy = true
        defer { busy = false }
        do {
            let data = try await request(["action": "start_provider", "thread_id": threadId, "provider": provider])
            let selected = try AtlasEnvironmentCoding.decode(AtlasEnvironmentSelection.self, from: data)
            try Task.checkCancellation()
            guard selected.thread.id == threadId else { throw CocoaError(.coderInvalidValue) }
            selection = selected.thread
            await load()
        } catch { if !Task.isCancelled { message = error.localizedDescription } }
    }
}
