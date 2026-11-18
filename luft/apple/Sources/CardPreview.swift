import SwiftUI

#if targetEnvironment(simulator)

/// A signed-out conversation with a plan and a card, for checking them on a simulator
/// before the server sends them: launch with `-LuftCardPreview`. The card is
/// `cards/bundle.js` at the 240 points the core gives a `medium` card; its
/// replies appear as the person's messages.
struct CardPreview: View {
    @State private var messages: [AppMessage] = [
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
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { item in
                        MessageRow(message: item) { text in
                            messages.append(Self.message(role: "user", content: text))
                        }
                    }
                }
                .padding()
            }
            .background(Noora.backgroundPrimary)
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

    private static func message(
        role: String, content: String, ui: [String: Any]? = nil, progress: [String: Any]? = nil
    ) -> AppMessage {
        var object: [String: Any] = ["id": UUID().uuidString, "role": role, "content": content]
        object["ui"] = ui
        object["progress"] = progress
        let data = try! JSONSerialization.data(withJSONObject: object)
        return try! JSONDecoder().decode(AppMessage.self, from: data)
    }
}
#endif
