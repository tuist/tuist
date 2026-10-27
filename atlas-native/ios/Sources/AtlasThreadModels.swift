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
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(updatedAt))
            ?? (try? Date.ISO8601FormatStyle().parse(updatedAt))
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct AtlasThreadComponent: Codable, Equatable {
    struct Table: Codable, Equatable {
        let title: String
        let columns: [String]
        let rows: [[String]]
    }
    struct Action: Codable, Equatable {
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

struct AtlasThreadMessage: Decodable, Identifiable, Equatable {
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

    var insertedDate: Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(insertedAt))
            ?? (try? Date.ISO8601FormatStyle().parse(insertedAt))
    }
}

struct AtlasThreadTimelineData {
    struct Group: Identifiable {
        let id: String
        var messages: [AtlasThreadMessage]
        let children: [AtlasThreadMessage]
        let date: Date?
        var tools: Bool { messages.count > 1 && messages.first?.kind == "tool" }
    }

    let groups: [Group]

    init(messages: [AtlasThreadMessage]) {
        let parents = Set(messages.filter { $0.kind == "tool" && $0.parentMessageId == nil }.map(\.id))
        var children: [String: [AtlasThreadMessage]] = [:]
        for message in messages where message.kind == "tool" {
            if let parent = message.parentMessageId, parents.contains(parent) {
                children[parent, default: []].append(message)
            }
        }
        var groups: [Group] = []
        var previousDate: Date?
        for message in messages {
            if message.kind == "tool", let parent = message.parentMessageId, parents.contains(parent) { continue }
            let date = message.insertedDate
            let sameDay = date.flatMap { date in previousDate.map { Calendar.current.isDate(date, inSameDayAs: $0) } } ?? false
            let last = groups.last?.messages.last
            if message.kind == "tool", message.component?.type != "account_card",
               last?.kind == "tool", last?.component?.type != "account_card",
               children[message.id] == nil, last.map({ children[$0.id] == nil }) == true, sameDay {
                groups[groups.count - 1].messages.append(message)
            } else {
                groups.append(Group(id: message.id, messages: [message], children: children[message.id] ?? [],
                                    date: sameDay ? nil : date))
            }
            previousDate = date
        }
        self.groups = groups
    }
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
        let statusFilter: String?
        let error: String?
        let liveMessage: String?
        let needsSession: Bool
    }
}
