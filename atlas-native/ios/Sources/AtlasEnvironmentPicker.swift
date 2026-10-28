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

    var body: some View {
        Form {
            Section {
                choice("Atlas server", environment: nil, project: nil)
                ForEach(overview?.environments.filter(\.enabled) ?? []) { environment in
                    Section(environment.name + (environment.online ? "" : " · Offline")) {
                        ForEach(environment.projects) { project in
                            choice(project.name, environment: environment.id, project: project.id)
                        }
                    }
                }
            } header: { Text("Tool environment") } footer: {
                Text("The conversation always runs on Atlas. This selection changes only where personal file and " +
                     "terminal tools execute. Local files stay on that Mac. Already running commands stay there until stopped.")
            }
            if let message { Text(message).foregroundStyle(.red) }
            if busy { ProgressView().controlSize(.small) }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(width: 380, height: 360)
        #endif
        .task(id: threadId) { await load() }
    }

    private func choice(_ name: String, environment: String?, project: String?) -> some View {
        Button {
            Task { await choose(environment: environment, project: project) }
        } label: {
            HStack {
                Text(name)
                Spacer()
                if selection?.environmentId == environment, selection?.projectId == project, selection != nil {
                    Image(systemName: "checkmark")
                }
            }
        }.buttonStyle(.plain).disabled(busy || selection == nil)
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
