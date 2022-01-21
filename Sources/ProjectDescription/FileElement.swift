import Foundation

/// File element
///
/// - glob: a glob pattern for files to include
/// - folderReference: a single path to a directory
///
/// Note: For convenience, an element can be represented as a string literal
///       `"some/pattern/**"` is the equivalent of `FileElement.glob(pattern: "some/pattern/**")`
public enum FileElement: Codable, Equatable {
    /// A glob pattern of files to include
    case glob(pattern: Path, group: String? = nil)

    /// Relative path to a directory to include
    /// as a folder reference
    case folderReference(path: Path, group: String? = nil)

    private enum TypeName: String, Codable {
        case glob
        case folderReference
    }

    private var typeName: TypeName {
        switch self {
        case .glob:
            return .glob
        case .folderReference:
            return .folderReference
        }
    }

    public enum CodingKeys: String, CodingKey {
        case type
        case pattern
        case path
        case group
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(TypeName.self, forKey: .type)
        let group = try container.decodeIfPresent(String.self, forKey: .group)
        switch type {
        case .glob:
            let pattern = try container.decode(Path.self, forKey: .pattern)
            self = .glob(pattern: pattern, group: group)
        case .folderReference:
            let path = try container.decode(Path.self, forKey: .path)
            self = .folderReference(path: path, group: group)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(typeName, forKey: .type)
        switch self {
        case let .glob(pattern: pattern, group: group):
            try container.encode(group, forKey: .group)
            try container.encode(pattern, forKey: .pattern)
        case let .folderReference(path: path, group: group):
            try container.encode(group, forKey: .group)
            try container.encode(path, forKey: .path)
        }
    }
}

extension FileElement: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self = .glob(pattern: Path(value))
    }
}

extension Array: ExpressibleByUnicodeScalarLiteral where Element == FileElement {
    public typealias UnicodeScalarLiteralType = String
}

extension Array: ExpressibleByExtendedGraphemeClusterLiteral where Element == FileElement {
    public typealias ExtendedGraphemeClusterLiteralType = String
}

extension Array: ExpressibleByStringLiteral where Element == FileElement {
    public typealias StringLiteralType = String

    public init(stringLiteral value: String) {
        self = [.glob(pattern: Path(value))]
    }
}
