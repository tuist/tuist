import Foundation

struct AtlasThreadPerson: Decodable, Identifiable {
    let id: String
    let name: String
}

struct AtlasThread: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let kind: String
    let status: String
    let summary: String
    let origin: String
    let ownerId: String?
    let participants: [AtlasThreadPerson]
    let updatedAt: String
    let agentStatus: String?

    var updatedDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: updatedAt) ?? ISO8601DateFormatter().date(from: updatedAt)
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct AtlasThreadComponent: Codable {
    struct Table: Codable {
        let title: String
        let columns: [String]
        let rows: [[String]]
    }
    struct Action: Codable {
        let id: String
        let label: String
    }
    let type: String
    let version: Int
    let data: Table
    let actions: [Action]
    let fallback: String
}

struct AtlasThreadAttachment: Decodable, Identifiable, Equatable {
    let id: String
    let filename: String
    let contentType: String
    let byteSize: Int
}

struct AtlasThreadMessage: Decodable, Identifiable {
    let id: String
    let kind: String
    let body: String
    let authorId: String?
    let authorName: String
    let insertedAt: String
    let toolName: String?
    let toolStatus: String?
    let parentMessageId: String?
    let toolInput: String
    let toolOutput: String
    let component: AtlasThreadComponent?
    let attachments: [AtlasThreadAttachment]?
    let noticeKind: String?
    let mentionedUserIds: [String]?
}

struct AtlasOrbitAssistant: Decodable {
    let name: String
    let configured: Bool
}

extension AtlasOrbit {
    struct Viewer: Decodable, Identifiable {
        let id: String
        let name: String
        let typing: Bool
    }
    struct Snapshot: Decodable {
        let sequence: UInt64
        let assistant: AtlasOrbitAssistant?
        let threads: [AtlasThread]
        let selected: AtlasThread?
        let messages: [AtlasThreadMessage]
        let people: [Viewer]
        let draft: String
        let draftMentions: [AtlasThreadPerson]?
        let mentionCandidates: [AtlasThreadPerson]?
        let mentionLoading: Bool?
        let mentionError: String?
        let draftAttachments: [AtlasThreadAttachment]?
        let attachmentBusy: Bool?
        let uploadPending: Bool?
        let uploadFilename: String?
        let loading: Bool
        let historyLoading: Bool
        let saving: Bool
        let hasMore: Bool
        let hasOlder: Bool
        let error: String?
        let liveMessage: String?
        let needsSession: Bool
    }
}
