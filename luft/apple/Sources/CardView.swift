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

struct AppDecision: Decodable {
    struct Option: Decodable, Identifiable {
        let id: String
        let label: String
    }
    struct Answer: Decodable {
        let option_id: String?
        let text: String
    }
    let question: String
    let options: [Option]
    let allow_other: Bool
    let status: String
    let answer: Answer?
}

/// Also used when NSH is unavailable or fails. Terminal decisions never run JS.
struct DecisionContent: View {
    let decision: AppDecision
    let answer: ((String?) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: decision.question).font(.headline).textSelection(.enabled)
            if decision.status == "pending" {
                ForEach(decision.options) { option in
                    Button { answer?(option.id) } label: {
                        Text(verbatim: option.label)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            } else if decision.status == "cancelled" {
                Text("Dismissed").foregroundStyle(Noora.labelSecondary)
            } else if let recorded = decision.answer {
                Text(verbatim: recorded.text).textSelection(.enabled)
            }
        }
    }
}

/// Shows a card at the height the core chose, so the conversation lays out
/// before the card runs and never resizes after it. Generic cards only fill
/// the composer with `reply`; pending decision cards can instead answer one
/// of that message's option IDs. macOS and failed cards use native fallback.
struct CardView: View {
    let card: AppCard
    let fallback: String
    var decision: AppDecision? = nil
    var answer: ((String?) -> Void)? = nil
    let reply: (String) -> Void
    @State private var failed = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        #if os(iOS)
        if failed {
            fallbackText
        } else {
            let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
            CardSurface(
                source: card.source,
                theme: Themes.shared.selected.cardOverrides(dark: colorScheme == .dark),
                decision: decision,
                answer: answer,
                reply: reply
            ) { failed = true }
                .frame(height: card.height)
                .clipShape(shape)
                .glass(in: shape)
                .accessibilityIdentifier("conversation-card")
        }
        #else
        fallbackText
        #endif
    }

    @ViewBuilder private var fallbackText: some View {
        if let decision {
            DecisionContent(decision: decision, answer: answer)
        } else {
            Text(verbatim: fallback).textSelection(.enabled).foregroundStyle(Noora.labelPrimary)
        }
    }
}

#if os(iOS)
private struct CardSurface: UIViewRepresentable {
    let source: String
    let theme: String?
    let decision: AppDecision?
    let answer: ((String?) -> Void)?
    let reply: (String) -> Void
    let failure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> NshAppView {
        let coordinator = context.coordinator
        coordinator.reply = reply
        coordinator.answer = answer
        coordinator.options = decision?.status == "pending" ? Set(decision?.options.map(\.id) ?? []) : []
        coordinator.failure = failure
        let view = NshAppView()
        // Clear, so the glass behind it shows through the card's clear surfaces.
        view.backgroundColor = .clear
        view.isOpaque = false
        applyTheme(to: view, coordinator)
        // A model's card runs untrusted: a small VM, no network, files or
        // clipboard, its own disposable storage, and one host function.
        view.limits = NshLimits(memoryMB: 32, loadBudget: 1, callBudget: 0.25, maxNodes: 2_000)
        view.storageDirectory = coordinator.directory.appendingPathComponent("storage")
        view.onError = { [weak coordinator] _ in coordinator?.failure?() }
        view.handle("reply") { [weak coordinator] data in
            if let text = data as? String, !text.isEmpty { coordinator?.reply?(text) }
            return nil
        }
        if decision?.status == "pending" {
            view.handle("answer") { [weak coordinator] data in
                guard let coordinator, let id = data as? String, coordinator.options.contains(id) else { return nil }
                coordinator.answer?(id)
                return nil
            }
        }
        do {
            // NSH allows what both the host grants and the app declares, and
            // a model's card declares nothing of its own.
            let capabilities = decision?.status == "pending" ? #"{"host":["answer"]}"# : #"{"host":["reply"]}"#
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
        context.coordinator.answer = answer
        context.coordinator.options = decision?.status == "pending" ? Set(decision?.options.map(\.id) ?? []) : []
        context.coordinator.failure = failure
        applyTheme(to: view, context.coordinator)
    }

    /// Restyles the card at once when the theme or appearance changes.
    private func applyTheme(to view: NshAppView, _ coordinator: Coordinator) {
        guard theme != coordinator.theme else { return }
        coordinator.theme = theme
        try? view.setThemeOverrides(theme)
    }

    static func dismantleUIView(_ view: NshAppView, coordinator: Coordinator) {
        view.onError = nil
        view.removeHandler("reply")
        view.removeHandler("answer")
        coordinator.reply = nil
        coordinator.answer = nil
        coordinator.failure = nil
        try? FileManager.default.removeItem(at: coordinator.directory)
    }

    final class Coordinator {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("luft-card-" + UUID().uuidString)
        var reply: ((String) -> Void)?
        var answer: ((String?) -> Void)?
        var options: Set<String> = []
        var failure: (() -> Void)?
        var theme: String?
    }
}
#endif
