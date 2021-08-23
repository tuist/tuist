import Foundation

/// Resource file elements
///
/// - resources: list of resource file elements
///
public struct ResourceFileElements: Codable, Equatable {
    /// List of resource file elements
    public let resources: [ResourceFileElement]
    public let excluding: [Path]

    public init(resources: [ResourceFileElement]) {
        self.resources = resources
        self.excluding = []
    }
    
    public init(resources: [ResourceFileElement], excluding: [Path]) throws {
        try excluding.forEach { path in
            if path.pathString.contains("/**/") {
                throw ResourceFileElementError.globsNotAllowed
            }
        }
        self.resources = resources
        self.excluding = []
    }
}

public enum ResourceFileElementError: Error {
    case globsNotAllowed
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
