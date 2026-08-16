/// Queries for matching against a target in manifests.
public enum TargetQuery: Codable, Equatable, Sendable, ExpressibleByStringLiteral {
    /// Match targets with the given name.
    case named(String)
    /// Match targets with the given metadata tag.
    case tagged(String)
    /// Match targets whose name matches the given glob pattern, for example `*-UnitTests`.
    ///
    /// The supported wildcards are `*` (any sequence of characters), `?` (any single character) and `[…]`
    /// (any character in the set).
    case matching(pattern: String)

    /// The wildcards that turn a string literal into a ``TargetQuery/matching(pattern:)`` query.
    private static let patternWildcards: Set<Character> = ["*", "?", "["]

    private enum CodingKeys: String, CodingKey {
        case named
        case tagged
        case matching
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let name = try container.decodeIfPresent(String.self, forKey: .named) {
            self = .named(name)
        } else if let tag = try container.decodeIfPresent(String.self, forKey: .tagged) {
            self = .tagged(tag)
        } else if let pattern = try container.decodeIfPresent(String.self, forKey: .matching) {
            self = .matching(pattern: pattern)
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid TargetQuery encoding")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .named(name):
            try container.encode(name, forKey: .named)
        case let .tagged(tag):
            try container.encode(tag, forKey: .tagged)
        case let .matching(pattern):
            try container.encode(pattern, forKey: .matching)
        }
    }

    public init(stringLiteral value: String) {
        let tagPrefix = "tag:"
        if value.hasPrefix(tagPrefix) {
            self = .tagged(String(value.dropFirst(tagPrefix.count)))
        } else if value.contains(where: Self.patternWildcards.contains) {
            self = .matching(pattern: value)
        } else {
            self = .named(value)
        }
    }
}
