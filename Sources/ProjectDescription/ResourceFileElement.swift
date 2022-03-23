import Foundation

/// A resource file element from a glob pattern or a folder reference.
///
/// - glob: a glob pattern for files to include
/// - folderReference: a single path to a directory
///
/// Note: For convenience, an element can be represented as a string literal
///       `"some/pattern/**"` is the equivalent of `ResourceFileElement.glob(pattern: "some/pattern/**")`
public enum ResourceFileElement: Codable, Equatable {
    /// A glob pattern of files to include and ODR tags
    case glob(pattern: Path, excluding: [Path] = [], tags: [String] = [])

    /// Relative path to a directory to include as a folder reference and ODR tags
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
}

extension ResourceFileElement: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self = .glob(pattern: Path(value))
    }
}
