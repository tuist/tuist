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

    var body: some View {
        Form {
            Section {
                choice("Atlas server", environment: nil, project: nil)
            } footer: {
                Text("Pip always runs on Atlas. Choose where its file and terminal tools run.")
            }
            ForEach(overview?.environments.filter(\.enabled) ?? []) { environment in
                Section {
                    ForEach(environment.projects) { project in
                        choice(project.name, environment: environment.id, project: project.id)
                    }
                    if environment.projects.isEmpty {
                        Text("No projects shared from this Mac.").foregroundStyle(.secondary)
                    }
                } header: {
                    Text(environment.name + (environment.online ? "" : " · Offline"))
                } footer: {
                    Text("Files stay on this Mac. Running commands stay there until stopped.")
                }
            }
            if overview?.environments.contains(where: \.enabled) == false {
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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        #else
        .frame(width: 380, height: 360)
        #endif
        .overlay { if busy { ProgressView().accessibilityLabel("Updating environment") } }
        .task(id: threadId) { await load() }
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
        } catch { message = error.localizedDescription }
    }
}
