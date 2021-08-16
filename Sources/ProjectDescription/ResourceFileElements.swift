import Foundation

/// Resource file elements
///
/// - resources: list of resource file elements
///
public struct ResourceFileElements: Codable, Equatable {
    /// List of resource file elements
    public let resources: [ResourceFileElement]
    public let excluding: [Path]

    public init(resources: [ResourceFileElement], excluding: [Path] = []) {
        self.resources = resources
        self.excluding = excluding
    }
}

extension ResourceFileElements: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self.init(resources: [.glob(pattern: Path(value))], excluding: [])
    }
}

extension ResourceFileElements: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: ResourceFileElement...) {
        self.init(resources: elements, excluding: [])
    }
}
