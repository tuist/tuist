#if os(iOS)
    import NativeShell
    import SwiftUI

    /// Source-only native renderer for installed modules. Generated conversation
    /// cards never use this surface or its data bridge. The host owns authorization.
    struct WorkspaceModuleSurface: UIViewRepresentable {
        let source: String
        let state: String
        let command: (Any?) async throws -> Any?
        let failure: () -> Void

        func makeCoordinator() -> Coordinator { Coordinator() }
        func makeUIView(context: Context) -> NshAppView {
            let view = NshAppView()
            let coordinator = context.coordinator
            view.limits = NshLimits(memoryMB: 32, loadBudget: 1, callBudget: 0.25, maxNodes: 4000)
            view.storageDirectory = coordinator.directory.appendingPathComponent("storage")
            view.onError = { _ in DispatchQueue.main.async { failure() } }
            view.handle("workspace") { data in try await command(data) }
            do {
                let capabilities = #"{"host":["workspace"]}"#
                try view.grantCapabilities(capabilities)
                try FileManager.default.createDirectory(at: coordinator.directory, withIntermediateDirectories: true)
                try Data(capabilities.utf8).write(to: coordinator.directory.appendingPathComponent("capabilities.json"))
                let bundle = coordinator.directory.appendingPathComponent("bundle.js")
                view.params = try JSONSerialization.jsonObject(with: Data(state.utf8)) as? [String: Any] ?? [:]
                coordinator.state = state
                try Data(source.utf8).write(to: bundle)
                try view.loadBundle(at: bundle)
            } catch {
                DispatchQueue.main.async { failure() }
            }
            return view
        }

        func updateUIView(_ view: NshAppView, context: Context) {
            guard context.coordinator.state != state,
                  let snapshot = try? JSONSerialization.jsonObject(with: Data(state.utf8)) else { return }
            context.coordinator.state = state
            view.send("workspace", snapshot)
        }

        static func dismantleUIView(_ view: NshAppView, coordinator: Coordinator) {
            view.onError = nil
            view.removeHandler("workspace")
            try? FileManager.default.removeItem(at: coordinator.directory)
        }

        final class Coordinator {
            var state = ""
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("luft-workspace-" + UUID().uuidString)
        }
    }
#endif
