import Foundation

/// Resource file element
///
/// - glob: a glob pattern for files to include
/// - folderReference: a single path to a directory
///
/// Note: For convenience, an element can be represented as a string literal
///       `"some/pattern/**"` is the equivalent of `ResourceFileElement.glob(pattern: "some/pattern/**")`
public enum ResourceFileElement: Codable, Equatable {
    /// A glob pattern of files to include
    /// and ODR tags
    case glob(pattern: Path, tags: [String] = [])

    /// Relative path to a directory to include
    /// as a folder reference
    /// and ODR tags
    case folderReference(path: Path, tags: [String] = [])

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
        case tags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(TypeName.self, forKey: .type)
        let tags = try? container.decode([String].self, forKey: .tags)
        switch type {
        case .glob:
            let pattern = try container.decode(Path.self, forKey: .pattern)
            self = .glob(pattern: pattern, tags: tags ?? [])
        case .folderReference:
            let path = try container.decode(Path.self, forKey: .path)
            self = .folderReference(path: path, tags: tags ?? [])
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(typeName, forKey: .type)
        switch self {
        case let .glob(pattern: pattern, tags: tags):
            try container.encode(pattern, forKey: .pattern)
            try container.encode(tags, forKey: .tags)
        case let .folderReference(path: path, tags: tags):
            try container.encode(path, forKey: .path)
            try container.encode(tags, forKey: .tags)
        }
    }
}

extension ResourceFileElement: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self = .glob(pattern: Path(value))
    }
}
