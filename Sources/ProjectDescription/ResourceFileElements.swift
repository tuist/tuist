import Foundation

/// A collection of resource file.
public struct ResourceFileElements: Codable, Equatable {
    /// List of resource file elements
    public let resources: [ResourceFileElement]

    public init(resources: [ResourceFileElement]) {
        self.resources = resources
    }
}

extension ResourceFileElements: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self.init(resources: [.glob(pattern: Path(value))])
    }
}

extension ResourceFileElements: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: ResourceFileElement...) {
        self.init(resources: elements)
    }
}
