/// A collection of resource file.
public struct ResourceFileElements: Codable, Equatable, Sendable, ExpressibleByStringInterpolation,
    ExpressibleByArrayLiteral
{
    /// List of resource file elements
    public var resources: [ResourceFileElement]

    /// Define your apps privacy manifest
    public var privacyManifest: PrivacyManifest?

    public static func resources(_ resources: [ResourceFileElement], privacyManifest: PrivacyManifest? = nil) -> Self {
        self.init(resources: resources, privacyManifest: privacyManifest)
    }

    public init(stringLiteral value: String) {
        self.init(resources: [.glob(pattern: .path(value))])
    }

    public init(arrayLiteral elements: ResourceFileElement...) {
        self.init(resources: elements)
    }
}
