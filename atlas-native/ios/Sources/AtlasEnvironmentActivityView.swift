import SwiftUI

struct AtlasEnvironmentActivityView: View {
    @StateObject private var model: AtlasEnvironmentActivity
    @Environment(\.scenePhase) private var scenePhase
    let enabled: Bool

    init(threadId: String, enabled: Bool, request: @escaping AtlasEnvironmentRequest) {
        self.enabled = enabled
        _model = StateObject(wrappedValue: AtlasEnvironmentActivity(threadId: threadId, request: request))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.commands) { job in
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(job.environmentName + " · " + job.projectName).font(.caption).foregroundStyle(.secondary)
                        Text(job.command).font(.callout.monospaced()).textSelection(.enabled)
                        if job.active && !job.cancelRequested {
                            Button(role: .destructive) { Task { await model.cancel(job) } } label: {
                                Text("Stop command").frame(minHeight: 44)
                            }
                            .accessibilityIdentifier("environment-stop")
                        }
                        if !job.output.isEmpty {
                            DisclosureGroup("Latest output") {
                                ScrollView([.horizontal, .vertical]) {
                                    Text(job.output).font(.caption.monospaced()).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 180)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label(job.phase, systemImage: "terminal")
                        .font(.subheadline.weight(.semibold))
                }
                .disabled(!enabled || scenePhase != .active || model.busy.contains(job.id) || model.message != nil)
            }
            if let message = model.message, !model.commands.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: enabled && scenePhase == .active) {
            if enabled && scenePhase == .active { await model.watch() } else { model.stop() }
        }
        .onDisappear { model.stop() }
        .protectsAtlasNavigation(!model.busy.isEmpty)
    }
}
