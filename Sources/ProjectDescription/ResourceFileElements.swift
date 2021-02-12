import Foundation

/// Resource file elements
///
/// - resources: list of resource file elements
///
public struct ResourceFileElements: Codable, Equatable {
    /// List of resource file elements
    public let resources: [ResourceFileElement]
}

extension ResourceFileElements: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(resources: [.glob(pattern: Path(value))])
    }
}

extension ResourceFileElements: ExpressibleByStringInterpolation {}

extension ResourceFileElements: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: ResourceFileElement...) {
        self.init(resources: elements)
    }
}
