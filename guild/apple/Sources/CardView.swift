import SwiftUI
#if os(iOS)
import NativeShell
#endif

/// A card a model wrote: NSH JavaScript and the frame height the Rust core
/// chose for its size class.
struct AppCard: Decodable {
    let height: CGFloat
    let source: String
}

/// Shows a card at the height the core chose, so the conversation lays out
/// before the card runs and never resizes after it. The card's only way out
/// is `host.call("reply", text)`, which fills the composer for the person
/// to send.
/// macOS has no NSH runtime yet, and a card that fails shows the message's
/// text instead.
struct CardView: View {
    let card: AppCard
    let fallback: String
    let reply: (String) -> Void
    @State private var failed = false

    var body: some View {
        #if os(iOS)
        if failed {
            fallbackText
        } else {
            CardSurface(source: card.source, reply: reply) { failed = true }
                .frame(height: card.height)
                .accessibilityIdentifier("conversation-card")
        }
        #else
        fallbackText
        #endif
    }

    private var fallbackText: some View {
        Text(verbatim: fallback).textSelection(.enabled).foregroundStyle(Noora.labelPrimary)
    }
}

#if os(iOS)
private struct CardSurface: UIViewRepresentable {
    let source: String
    let reply: (String) -> Void
    let failure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> NshAppView {
        let coordinator = context.coordinator
        coordinator.reply = reply
        coordinator.failure = failure
        let view = NshAppView()
        // A model's card runs untrusted: a small VM, no network, files or
        // clipboard, its own disposable storage, and one host function.
        view.limits = NshLimits(memoryMB: 32, loadBudget: 1, callBudget: 0.25, maxNodes: 2_000)
        view.storageDirectory = coordinator.directory.appendingPathComponent("storage")
        view.onError = { [weak coordinator] _ in coordinator?.failure?() }
        view.handle("reply") { [weak coordinator] data in
            if let text = data as? String, !text.isEmpty { coordinator?.reply?(text) }
            return nil
        }
        do {
            // NSH allows what both the host grants and the app declares, and
            // a model's card declares nothing of its own.
            let capabilities = #"{"host":["reply"]}"#
            try view.grantCapabilities(capabilities)
            // Source, not bytecode: NSH only trusts bytecode from the app bundle.
            try FileManager.default.createDirectory(at: coordinator.directory, withIntermediateDirectories: true)
            try Data(capabilities.utf8).write(to: coordinator.directory.appendingPathComponent("capabilities.json"))
            let bundle = coordinator.directory.appendingPathComponent("bundle.js")
            try Data(source.utf8).write(to: bundle)
            try view.loadBundle(at: bundle)
        } catch {
            DispatchQueue.main.async { failure() }
        }
        return view
    }

    func updateUIView(_ view: NshAppView, context: Context) {
        context.coordinator.reply = reply
        context.coordinator.failure = failure
    }

    static func dismantleUIView(_ view: NshAppView, coordinator: Coordinator) {
        view.onError = nil
        view.removeHandler("reply")
        coordinator.reply = nil
        coordinator.failure = nil
        try? FileManager.default.removeItem(at: coordinator.directory)
    }

    final class Coordinator {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("guild-card-" + UUID().uuidString)
        var reply: ((String) -> Void)?
        var failure: (() -> Void)?
    }
}
#endif
