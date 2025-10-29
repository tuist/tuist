public enum PackageSettingsTrait: ExpressibleByStringLiteral, Codable, Hashable, Equatable, Sendable {
    case named(String)
    case `default`

    public init(stringLiteral value: StringLiteralType) {
        self = .named(value)
    }
}
