import Foundation

/// One of the signed-in user's notification rules: when `event` happens in one of `projects` (any project when it's
/// empty) and the event meets the conditions, run `actions`. Today the only event is `preview_published` and the only
/// action is `push`.
public struct ServerNotificationRule: Identifiable, Hashable, Sendable {
    public static let previewPublished = "preview_published"
    public static let push = "push"

    /// A text condition: one exact value, or text it contains, ignoring case.
    public enum ValueMatch: Hashable, Sendable {
        case `is`(String)
        case contains(String)
    }

    public var id: String
    public var event: String
    public var isEnabled: Bool
    /// `account/project` handles.
    public var projects: [String]
    public var track: ValueMatch?
    public var gitBranch: ValueMatch?
    /// Only previews the user published.
    public var publishedByMe: Bool
    public var actions: [String]

    public init(
        id: String = "",
        event: String = ServerNotificationRule.previewPublished,
        isEnabled: Bool = true,
        projects: [String] = [],
        track: ValueMatch? = nil,
        gitBranch: ValueMatch? = nil,
        publishedByMe: Bool = false,
        actions: [String] = [ServerNotificationRule.push]
    ) {
        self.id = id
        self.event = event
        self.isEnabled = isEnabled
        self.projects = projects
        self.track = track
        self.gitBranch = gitBranch
        self.publishedByMe = publishedByMe
        self.actions = actions
    }
}

/// The JSON shape of a rule, shared by every operation's generated payload type.
struct NotificationRulePayload: Codable {
    struct Match: Codable {
        var `operator`: String
        var value: String

        init(operator: String, value: String) {
            self.operator = `operator`
            self.value = value
        }

        init(_ match: ServerNotificationRule.ValueMatch) {
            switch match {
            case let .is(value): self.init(operator: "is", value: value)
            case let .contains(value): self.init(operator: "contains", value: value)
            }
        }

        var valueMatch: ServerNotificationRule.ValueMatch? {
            switch `operator` {
            case "is": .is(value)
            case "contains": .contains(value)
            default: nil
            }
        }
    }

    struct Conditions: Codable {
        var track: Match?
        var gitBranch: Match?
        var publishedBy: String?

        enum CodingKeys: String, CodingKey {
            case track
            case gitBranch = "git_branch"
            case publishedBy = "published_by"
        }
    }

    struct Action: Codable {
        var type: String
    }

    var id: String?
    var event: String?
    var enabled: Bool?
    var projects: [String]?
    var conditions: Conditions?
    var actions: [Action]?

    init(_ rule: ServerNotificationRule, includingEvent: Bool) {
        event = includingEvent ? rule.event : nil
        enabled = rule.isEnabled
        projects = rule.projects
        conditions = Conditions(
            track: rule.track.map(Match.init),
            gitBranch: rule.gitBranch.map(Match.init),
            publishedBy: rule.publishedByMe ? "me" : "anyone"
        )
        actions = rule.actions.map(Action.init(type:))
    }

    var rule: ServerNotificationRule {
        ServerNotificationRule(
            id: id ?? "",
            event: event ?? "",
            isEnabled: enabled ?? true,
            projects: projects ?? [],
            track: conditions?.track.flatMap(\.valueMatch),
            gitBranch: conditions?.gitBranch.flatMap(\.valueMatch),
            publishedByMe: conditions?.publishedBy == "me",
            actions: actions?.map(\.type) ?? []
        )
    }

    /// Converts between this payload and a generated one by way of their shared JSON.
    static func convert<Output: Decodable>(_ value: some Encodable, to _: Output.Type = Output.self) throws -> Output {
        try JSONDecoder().decode(Output.self, from: JSONEncoder().encode(value))
    }
}
