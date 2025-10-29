/// Represents a package traits to configure the traits that we should include for certain product.
/// When no trait is provided, the default trait specified by the package product is used.
public enum PackageSettingsTrait: ExpressibleByStringLiteral, Codable, Hashable, Equatable, Sendable {
    /// The name of the product trait to use.
    case named(String)

    /// When used, it takes the default trait of the package.
    case `default`

    public init(stringLiteral value: StringLiteralType) {
        self = .named(value)
    }
}
