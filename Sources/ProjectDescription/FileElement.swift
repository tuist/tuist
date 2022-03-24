import Foundation

/// A file element from a glob pattern or a folder reference.
///
/// - glob: a glob pattern for files to include
/// - folderReference: a single path to a directory
///
/// Note: For convenience, an element can be represented as a string literal
///       `"some/pattern/**"` is the equivalent of `FileElement.glob(pattern: "some/pattern/**")`
public enum FileElement: Codable, Equatable {
    /// A file path (or glob pattern) to include. For convenience, a string literal can be used as an alternate way to specify this option.
    case glob(pattern: Path)

    /// A directory path to include as a folder reference.
    case folderReference(path: Path)

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
