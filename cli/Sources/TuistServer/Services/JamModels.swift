import Foundation

public struct JamModel: Codable, Hashable {
    public let provider: String
    public let id: String
    public let name: String

    public init(provider: String, id: String, name: String) {
        self.provider = provider
        self.id = id
        self.name = name
    }

    public var providerName: String {
        switch provider {
        case "chatgpt": "ChatGPT"
        case "claude": "Claude"
        default: provider
        }
    }
}

public struct JamModelCatalog: Decodable {
    public let models: [JamModel]
    public let errors: [ProviderError]

    public struct ProviderError: Decodable, Hashable {
        public let provider: String
        public let code: String
    }
}

public struct DemoJam: Codable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let goal: String
    public let repository: String
    public let branch: String
    public let profile: String
    public let provider: String?
    public let model: String?
    public var status: String
    public var visibility: String
    public var messages: [JamMessage]
    public let diff: String
    public var revision: Int?
    public var hasMore: Bool?
    public var nextBefore: Int?
    public var archiveStatus: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, goal, repository, branch, profile, provider, model, status, visibility, messages, diff, revision
        case hasMore = "has_more"
        case nextBefore = "next_before"
        case archiveStatus = "archive_status"
    }

    public init(
        id: String, title: String, repository: String, profile: String, status: String,
        visibility: String, messages: [JamMessage], diff: String = "", goal: String? = nil,
        branch: String = "jams/preview", provider: String? = nil, model: String? = nil
    ) {
        self.id = id
        self.title = title
        self.goal = goal ?? title
        self.repository = repository
        self.branch = branch
        self.profile = profile
        self.provider = provider
        self.model = model
        self.status = status
        self.visibility = visibility
        self.messages = messages
        self.diff = diff
    }

    public var isRunning: Bool { ["queued", "running", "compacting", "shipping"].contains(status) }

    public func mergingHistory(_ page: DemoJam, older: Bool = false) -> DemoJam {
        guard page.id == id else { return self }
        if !older, (page.revision ?? 0) < (revision ?? 0) { return self }
        var result = older ? self : page
        let first = page.messages.compactMap(\.position).min()
        let last = messages.compactMap(\.position).max()
        if !older, let first, let last, first > last + 1 { return page }
        let incomingIDs = Set(page.messages.map(\.id))
        if older {
            let existingIDs = Set(messages.map(\.id))
            result.messages = page.messages.filter { !existingIDs.contains($0.id) } + messages
            result.hasMore = page.hasMore
            result.nextBefore = page.nextBefore == nextBefore ? nil : page.nextBefore
            if result.nextBefore == nil { result.hasMore = false }
        } else {
            let prefix = messages.filter { message in
                !incomingIDs.contains(message.id) && (message.position ?? Int.max) < (first ?? Int.min)
            }
            result.messages = prefix + page.messages
            if !prefix.isEmpty {
                result.hasMore = hasMore
                result.nextBefore = nextBefore
            }
        }
        return result
    }

    public var suggestedPrompts: [String] {
        guard !isRunning, status != "outcome_unknown",
              let latest = messages.last(where: { $0.role != "tool" && $0.role != "system" }),
              latest.role == "assistant"
        else { return [] }
        var seen = Set<String>()
        return Array((latest.suggestions ?? []).filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 200 && seen.insert($0).inserted
        }.prefix(3))
    }
}

public struct JamMessage: Codable, Identifiable, Hashable {
    public let id: String
    public let role: String
    public let content: String
    public let suggestions: [String]?
    public let toolName: String?
    public let toolStatus: String?
    public let toolInput: String?
    public let parentMessageID: String?
    public let richContent: JamRichContent?
    public let position: Int?

    public init(
        id: String, role: String, content: String, suggestions: [String]? = nil,
        toolName: String? = nil, toolStatus: String? = nil, toolInput: String? = nil,
        parentMessageID: String? = nil, richContent: JamRichContent? = nil, position: Int? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.suggestions = suggestions
        self.toolName = toolName
        self.toolStatus = toolStatus
        self.toolInput = toolInput
        self.parentMessageID = parentMessageID
        self.richContent = richContent
        self.position = position
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, content, suggestions, toolName, toolStatus, toolInput, parentMessageID, richContent, position
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        role = try values.decode(String.self, forKey: .role)
        content = try values.decode(String.self, forKey: .content)
        suggestions = try values.decodeIfPresent([String].self, forKey: .suggestions)
        toolName = try values.decodeIfPresent(String.self, forKey: .toolName)
        toolStatus = try values.decodeIfPresent(String.self, forKey: .toolStatus)
        toolInput = try values.decodeIfPresent(String.self, forKey: .toolInput)
        parentMessageID = try values.decodeIfPresent(String.self, forKey: .parentMessageID)
        position = try values.decodeIfPresent(Int.self, forKey: .position)
        // An unsupported presentation must not hide the original conversation.
        richContent = try? values.decode(JamRichContent.self, forKey: .richContent)
    }
}

public struct JamRichContent: Codable, Hashable {
    public let kind: String
    public let title: String
    public let summary: String
    public let facts: [Fact]
    public let details: [String]

    public struct Fact: Codable, Hashable {
        public let label: String
        public let value: String

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    public init(kind: String, title: String, summary: String, facts: [Fact], details: [String]) {
        self.kind = kind
        self.title = title
        self.summary = summary
        self.facts = facts
        self.details = details
    }
}
