import Foundation
#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

/// A query that matches one or more targets of a graph.
public enum TargetQuery: Equatable, Hashable, Codable, Sendable {
    /// Matches the target with the given name.
    case named(String)
    /// Matches the targets with the given metadata tag.
    case tagged(String)
    /// Matches the targets whose name matches the given glob pattern, for example `*-UnitTests`.
    case matching(pattern: String)

    /// Returns whether a target with the given name and tags is matched by the query.
    public func matches(targetName: String, tags: Set<String>) -> Bool {
        switch self {
        case let .named(name):
            return targetName == name
        case let .tagged(tag):
            return tags.contains(tag)
        case let .matching(pattern):
            return fnmatch(pattern, targetName, 0) == 0
        }
    }

    /// Returns whether the given target is matched by the query.
    public func matches(_ target: Target) -> Bool {
        matches(targetName: target.name, tags: target.metadata.tags)
    }
}
