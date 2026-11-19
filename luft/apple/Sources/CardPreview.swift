import SwiftUI

#if targetEnvironment(simulator) || os(macOS)

/// A signed-out conversation with a plan and a card, for checking them on a simulator
/// before the server sends them: launch with `-LuftCardPreview`. The card is
/// `cards/bundle.js` at the 240 points the core gives a `medium` card; its
/// replies fill a composer. Decisions exercise NSH, native fallback and both
/// terminal states without signing in or creating a server conversation.
struct CardPreview: View {
    @State private var reply = ""
    @State private var messages: [AppMessage] = initialMessages

    private static var initialMessages: [AppMessage] {
        if ProcessInfo.processInfo.arguments.contains("-LuftDecisionPreview") {
            return [
                message(role: "user", content: "Help me investigate our slow builds."),
                decisionMessage(status: "pending", ui: ["height": 240, "source": decisionSource]),
            ]
        }
        return [
            message(role: "user", content: "Which targets slow our builds down this week?"),
            message(role: "system", content: "", progress: [
                "steps": [
                    ["title": "Read this week's build runs", "status": "completed"],
                    ["title": "Rank targets by build time", "status": "completed"],
                    ["title": "Check their cache hits", "status": "in_progress"],
                    ["title": "Summarize the slowest", "status": "pending"],
                ],
                "completed": 2, "total": 4, "active": true,
            ]),
            message(
                role: "assistant",
                content: "TuistKit is the slowest: 412 s median, 31% cache hits.",
                ui: ["height": 240, "source": source]
            ),
            message(role: "assistant", content: "TuistKit misses the cache most. Want me to look into why?"),
            decisionMessage(status: "pending", ui: ["height": 240, "source": decisionSource]),
            decisionMessage(status: "pending", ui: ["height": 240, "source": "throw new Error('Preview fallback')"]),
            decisionMessage(status: "answered"),
            decisionMessage(status: "cancelled"),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { item in
                        MessageRow(message: item, answer: { option in
                            record(item, option: option)
                        }) { text in reply = text }
                    }
                }
                .padding()
            }
            .background(Noora.backgroundPrimary)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    TextField("Reply", text: $reply)
                    Button("Send") {
                        if let pending = messages.last(where: { $0.decision?.status == "pending" }) {
                            record(pending, option: nil, text: reply)
                        }
                        messages.append(Self.message(role: "user", content: reply))
                        reply = ""
                    }
                    .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding().background(Noora.backgroundPrimary)
            }
            .navigationTitle(Text(verbatim: "Build times"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private static var source: String {
        Bundle.main.url(forResource: "bundle", withExtension: "js")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    private static var decisionSource: String {
        Bundle.main.url(forResource: "decision-bundle", withExtension: "js")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    private func record(_ message: AppMessage, option: String?, text: String? = nil) {
        guard let index = messages.firstIndex(where: { $0.id == message.id }),
              let decision = messages[index].decision, decision.status == "pending" else { return }
        let label = text ?? decision.options.first(where: { $0.id == option })?.label
        messages[index].decision = AppDecision(
            question: decision.question, options: decision.options, allow_other: decision.allow_other,
            status: label == nil ? "cancelled" : "answered",
            answer: label.map { AppDecision.Answer(option_id: option, text: $0) }
        )
        messages[index].ui = nil
    }

    private static func decisionMessage(status: String, ui: [String: Any]? = nil) -> AppMessage {
        message(role: "assistant", content: "How should we investigate the slow builds?", ui: ui, decision: [
            "question": "How should we investigate the slow builds?",
            "options": [
                ["id": "cache", "label": "Investigate cache misses, including changes to build settings and dependencies that invalidate otherwise reusable targets"],
                ["id": "timing", "label": "Compare build timings"],
                ["id": "later", "label": "Leave the investigation for later"],
            ],
            "allow_other": true, "status": status,
            "answer": status == "answered" ? ["option_id": "timing", "text": "Compare build timings"] : NSNull(),
        ])
    }

    private static func message(
        role: String, content: String, ui: [String: Any]? = nil, progress: [String: Any]? = nil,
        decision: [String: Any]? = nil
    ) -> AppMessage {
        var object: [String: Any] = ["id": UUID().uuidString, "role": role, "content": content]
        object["ui"] = ui
        object["progress"] = progress
        object["decision"] = decision
        let data = try! JSONSerialization.data(withJSONObject: object)
        return try! JSONDecoder().decode(AppMessage.self, from: data)
    }
}

/// Simulator-only evidence fixture: `-LuftToolPreview`.
struct ToolPreview: View {
    private let cases: [AppToolResult.TestCase] = [
        .init(name: "shard_with_remote_test_products()", module: "TuistServerAcceptanceTests", suite: "ShardAcceptanceTests", flaky: true, state: "muted"),
        .init(name: "test_run_tests_with_specified_arch()", module: "TuistKitTests", suite: "TestServiceTests", flaky: true, state: "muted"),
        .init(name: "cancelledReadsRetainCapacityUntilBackendCleanupFinishes()", module: "TuistCargoCommandTests", suite: "CargoRemoteCacheTests", flaky: true, state: "muted"),
        .init(name: "givesUpOnADrainThatOutlastsTheRetryWindow()", module: "TuistCacheEEClientTests", suite: "REAPICacheClientTests", flaky: false, state: "active"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: "Can you give me the most flaky tests of tuist/tuist?")
                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(Noora.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12))
                    ToolCallRow(tool: tool)
                    ToolCallRow(tool: AppMessage(id: "plain", role: "tool", content: "Build succeeded.\n" + String(repeating: "Checked target successfully.\n", count: 20), toolName: "Bash", toolStatus: "complete"))
                    ToolCallRow(tool: AppMessage(id: "running", role: "tool", content: "", toolName: "tuist_list_build_runs", toolStatus: "running"))
                }.padding()
            }
            .background(Noora.backgroundPrimary)
            .navigationTitle(Text(verbatim: "Test results"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private var tool: AppMessage {
        let payload: [String: Any] = ["test_cases": cases.map {
            ["name": $0.name, "module_name": $0.module!, "suite_name": $0.suite!, "is_flaky": $0.flaky!, "state": $0.state!] as [String: Any]
        }]
        let text = String(data: try! JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!
        let envelope: [String: Any] = ["content": [["type": "text", "text": text]]]
        let raw = String(data: try! JSONSerialization.data(withJSONObject: envelope), encoding: .utf8)!
        let formatted = String(data: try! JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!
        return AppMessage(id: "tests", role: "tool", content: raw, toolName: "tuist_list_test_cases", toolStatus: "complete",
                          toolResult: AppToolResult(text: text, preview: String(text.prefix(1200)), raw: formatted, testCases: cases))
    }
}
#endif
