/// Queries for matching against a target.
public enum TargetQuery: Codable, Hashable, Sendable {
    /// Match targets with the given name.
    case named(String)
    /// Match targets with the given metadata tag.
    case tagged(String)
}

extension TargetQuery: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        let tagPrefix = "tag:"
        if value.hasPrefix(tagPrefix) {
            self = .tagged(String(value.dropFirst(tagPrefix.count)))
        } else {
            self = .named(value)
        }
    }
}
