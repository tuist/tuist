import ActivityKit
import Foundation

// Keep the ActivityKit wire types and their CodingKeys scoped to the attributes.
// swiftlint:disable nesting
struct AtlasActivityAttributes: ActivityAttributes {
    struct Conversation: Codable, Hashable, Identifiable {
        enum Status: String, Codable {
            case queued, running, compacting
            case usingTools = "using_tools"

            var label: String {
                switch self {
                case .queued: "Getting ready"
                case .running: "Thinking"
                case .compacting: "Organizing context"
                case .usingTools: "Working with tools"
                }
            }

            var symbol: String {
                switch self {
                case .queued: "clock"
                case .running: "sparkles"
                case .compacting: "square.stack.3d.up"
                case .usingTools: "wrench.and.screwdriver"
                }
            }
        }

        let id: String
        let status: Status
        let startedAt: TimeInterval
        let completedSteps: Int
        let title: String?

        var displayTitle: String { title.flatMap { $0.isEmpty ? nil : $0 } ?? "Conversation" }

        enum CodingKeys: String, CodingKey {
            case id, status, title
            case startedAt = "started_at"
            case completedSteps = "completed_steps"
        }
    }

    struct ContentState: Codable, Hashable {
        let activeCount: Int
        let conversations: [Conversation]
        let updatedAt: TimeInterval

        var startedAt: Date? { conversations.map { Date(timeIntervalSince1970: $0.startedAt) }.min() }
        var isEmpty: Bool { activeCount == 0 }

        enum CodingKeys: String, CodingKey {
            case conversations
            case activeCount = "active_count"
            case updatedAt = "updated_at"
        }
    }

    let registrationID: String
    let server: String

    func destination(for conversation: Conversation? = nil) -> URL? {
        guard let origin = URL(string: server), origin.scheme == "https", origin.host != nil else { return nil }
        var url = URLComponents()
        url.scheme = "dev.tuist.atlas"
        url.host = "navigate"
        url.path = "/orbit"
        if let conversation, UUID(uuidString: conversation.id) != nil { url.path += "/" + conversation.id }
        url.queryItems = [URLQueryItem(name: "server", value: server)]
        return url.url
    }
}
// swiftlint:enable nesting
