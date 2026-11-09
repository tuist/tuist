#if os(iOS)
    import SwiftUI
    import TuistServer
    #if canImport(NativeShell)
        import NativeShell
    #endif

    struct JamConversationRichContent: View {
        let message: JamMessage
        @State private var failed = false
        @State private var height: CGFloat = 280
        @State private var receivedLayout = false

        var body: some View {
            #if canImport(NativeShell)
                if !failed, let content = message.richContent, supported(content),
                   let bundle = Bundle.main.url(forResource: "bundle", withExtension: "nshc", subdirectory: "ui")
                {
                    VStack(alignment: .leading, spacing: 8) {
                        JamNativeCard(bundle: bundle, content: content, resized: { value in
                            guard value.isFinite, value > 0, value <= 4096 else { failed = true; return }
                            receivedLayout = true
                            if abs(height - value) > 1 { height = value }
                        }, failed: { failed = true })
                            .frame(height: height)
                            .task {
                                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                                if !receivedLayout { failed = true }
                            }
                        DisclosureGroup {
                            JamConversationMarkdown(source: message.content)
                        } label: {
                            Text("Original response").frame(minHeight: 44)
                        }
                        .font(.caption)
                        .tint(.secondary)
                    }
                } else {
                    JamConversationMarkdown(source: message.content)
                }
            #else
                JamConversationMarkdown(source: message.content)
            #endif
        }

        private func supported(_ content: JamRichContent) -> Bool {
            ["test_results", "change_summary"].contains(content.kind)
                && content.title.count <= 120 && content.summary.count <= 1000
                && content.facts.count <= 6 && content.details.count <= 8
                && content.facts.allSatisfy { $0.label.count <= 80 && $0.value.count <= 160 }
                && content.details.allSatisfy { $0.count <= 800 }
        }
    }

    #if canImport(NativeShell)
        private struct JamNativeCard: UIViewRepresentable {
            let bundle: URL
            let content: JamRichContent
            let resized: (CGFloat) -> Void
            let failed: () -> Void

            func makeUIView(context _: Context) -> NshAppView {
                let view = NshAppView()
                view.clipsToBounds = true
                view.backgroundColor = .clear
                // NSH 0.3.0's error callback crashes; missing initial layout triggers the Markdown fallback.
                view.handle("layout.height") { data, reply in
                    if let value = data as? NSNumber {
                        Task { @MainActor in resized(CGFloat(value.doubleValue).rounded(.up)) }
                    }
                    reply.resolve()
                }
                do {
                    try view.grantCapabilities(#"{"host":["layout.height"]}"#)
                    view.limits = NshLimits(memoryMB: 32, loadBudget: 2, callBudget: 0.2, maxNodes: 1000)
                    view.cacheOptions = NshCacheOptions(location: .off, images: .off)
                    view.params = [
                        "kind": content.kind, "title": content.title, "summary": content.summary,
                        "facts": content.facts.map { ["label": $0.label, "value": $0.value] },
                        "details": content.details,
                    ]
                    try view.loadBundle(at: bundle)
                } catch {
                    Task { @MainActor in failed() }
                }
                return view
            }

            func updateUIView(_: NshAppView, context _: Context) {}

            static func dismantleUIView(_ view: NshAppView, coordinator _: ()) {
                view.removeHandler("layout.height")
            }
        }
    #endif
#endif
