import SwiftUI

struct AtlasThreadModelButton: View {
    @ObservedObject var model: AtlasOrbit
    let thread: AtlasThread
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(model.models.first { $0.id == thread.model }?.name
                    ?? thread.model?.replacingOccurrences(of: "chatgpt:", with: "") ?? "Automatic")
                Image(systemName: "chevron.up.chevron.down").imageScale(.small)
            }
            .font(.subheadline).frame(minHeight: 44)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.borderless).foregroundStyle(.secondary)
        .modifier(AtlasComposerSurface(shape: Capsule(), interactive: true))
        .accessibilityLabel("Model").accessibilityValue(thread.model ?? "Automatic")
        .accessibilityIdentifier("thread-model")
        .disabled(!enabled || ["queued", "running", "compacting"].contains(thread.agentStatus ?? ""))
    }
}

struct AtlasThreadModelPicker: View {
    @ObservedObject var model: AtlasOrbit
    let threadId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    choice(id: nil, name: "Automatic")
                } footer: {
                    Text("Uses your connected AI accounts, with the workspace model as a fallback.")
                }
                ForEach(["ChatGPT", "Atlas"], id: \.self) { provider in
                    let choices = model.models.filter { $0.provider == provider }
                    if !choices.isEmpty {
                        Section(provider) {
                            ForEach(choices) { item in choice(id: item.id, name: item.name) }
                        }
                    }
                }
                if let selected = model.selected?.model, !model.models.contains(where: { $0.id == selected }) {
                    Section("Selected model") {
                        Text(selected.replacingOccurrences(of: "chatgpt:", with: ""))
                        Text("This model is not in the available list. Choose another model or reconnect your AI account.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Section {
                    if model.modelsLoading {
                        ProgressView("Loading models…")
                    } else if let error = model.modelError {
                        Text(error).foregroundStyle(.secondary).accessibilityIdentifier("thread-model-error")
                        Button("Try again") { Task { await model.loadModels() } }
                    } else if model.models.isEmpty {
                        Text("Connect ChatGPT in Settings → AI accounts to choose a model.").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Your choice is saved for this conversation. A selected model never switches providers automatically.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Model")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .frame(idealWidth: 440, idealHeight: 480)
        .task { await model.loadModels() }
    }

    private func choice(id: String?, name: String) -> some View {
        Button {
            Task { await model.setModel(id, threadId: threadId) }
        } label: {
            HStack {
                Text(name).foregroundStyle(.primary)
                Spacer()
                if model.selected?.model == id { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(model.saving || model.selected?.id != threadId)
        .accessibilityIdentifier("thread-model-\(id ?? "automatic")")
        .accessibilityAddTraits(model.selected?.model == id ? .isSelected : [])
    }
}

struct AtlasThreadInfo: View {
    let thread: AtlasThread
    let assistantName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Thread") {
                    if thread.kind == "private" { Label("Only you and \(assistantName)", systemImage: "lock") }
                    if !thread.summary.isEmpty { Text(thread.summary) }
                    if !thread.origin.isEmpty { LabeledContent("Started from", value: thread.origin.capitalized) }
                    LabeledContent("Status", value: thread.status.capitalized)
                }
                if thread.kind != "private" {
                    Section("Participants") {
                        Label(assistantName, systemImage: "sparkles")
                        ForEach(thread.participants) { Text($0.name) }
                    }
                }
            }
            .navigationTitle("Thread details")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(idealWidth: 440, idealHeight: 400)
        #endif
        .presentationDetents([.medium, .large])
    }
}
