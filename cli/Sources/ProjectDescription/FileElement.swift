/// A file element from a glob pattern or a folder reference.
///
/// - glob: a glob pattern for files to include
/// - folderReference: a single path to a directory
///
/// Note: For convenience, an element can be represented as a string literal
///       `"some/pattern/**"` is the equivalent of `FileElement.glob(pattern: "some/pattern/**")`
public enum FileElement: Codable, Equatable, Sendable {
    /// A file path (or glob pattern) to include, with optional exclusions.
    ///
    /// For convenience, a string literal can be used as an alternate way to specify this option.
    ///
    /// - Parameters:
    ///   - pattern: A glob pattern for files to include.
    ///   - excluding: An array of glob patterns to exclude from the matched files.
    ///
    /// Example:
    /// ```swift
    /// .glob(pattern: "Documentation/**/*.md", excluding: ["Documentation/internal/**"])
    /// ```
    case glob(pattern: Path, excluding: [Path] = [])

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
        self = .glob(pattern: .path(value))
    }
}

extension [FileElement]: @retroactive ExpressibleByUnicodeScalarLiteral {
    public typealias UnicodeScalarLiteralType = String
}

extension [FileElement]: @retroactive ExpressibleByExtendedGraphemeClusterLiteral {
    public typealias ExtendedGraphemeClusterLiteralType = String
}

extension [FileElement]: @retroactive ExpressibleByStringLiteral {
    public typealias StringLiteralType = String

    public init(stringLiteral value: String) {
        self = [.glob(pattern: .path(value))]
    }
}
