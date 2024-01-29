import Foundation

/// A collection of resource file.
public struct ResourceFileElements: Codable, Equatable {
    /// List of resource file elements
    public var resources: [ResourceFileElement]

    public static func resources(_ resources: [ResourceFileElement]) -> Self {
        self.init(resources: resources)
    }
}

extension ResourceFileElements: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self.init(resources: [.glob(pattern: .path(value))])
    }
}

extension ResourceFileElements: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: ResourceFileElement...) {
        self.init(resources: elements)
    }
}
