#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

/// Queries for matching against a target.
public enum TargetQuery: Codable, Hashable, Sendable, ExpressibleByStringLiteral {
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

/// Matches targets against a collection of ``TargetQuery``.
public struct TargetQueryMatcher: Equatable, Sendable {
    private let names: Set<String>
    private let tags: Set<String>
    private let patterns: [String]

    public init(_ queries: some Sequence<TargetQuery>) {
        var names = Set<String>()
        var tags = Set<String>()
        var patterns = [String]()
        for query in queries {
            switch query {
            case let .named(name):
                names.insert(name)
            case let .tagged(tag):
                tags.insert(tag)
            case let .matching(pattern):
                patterns.append(pattern)
            }
        }
        self.names = names
        self.tags = tags
        self.patterns = patterns
    }

    /// Whether there's no query to match targets against.
    public var isEmpty: Bool {
        names.isEmpty && tags.isEmpty && patterns.isEmpty
    }

    /// Returns whether a target with the given name and tags is matched by any of the queries.
    public func matches(targetName: String, tags: Set<String>) -> Bool {
        if names.contains(targetName) { return true }
        if !self.tags.isDisjoint(with: tags) { return true }
        return patterns.contains { fnmatch($0, targetName, 0) == 0 }
    }
}
