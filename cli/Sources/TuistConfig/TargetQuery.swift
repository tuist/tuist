public enum TargetQuery: Codable, Hashable, Sendable {
    case named(String)
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
