import Foundation

/// A file element from a glob pattern or a folder reference which is conditionally applied to specific platforms with an optional
/// "Code Sign On Copy" flag.
public enum CopyFileElement: Codable, Equatable, Sendable {
    /// A file path (or glob pattern) to include with an optional PlatformCondition to control which platforms it applies.
    /// "Code Sign on Copy" can be optionally enabled for the glob.
    case glob(pattern: Path, condition: PlatformCondition? = nil, codeSignOnCopy: Bool = false)

    /// A directory path to include as a folder reference with an optional PlatformCondition to control which platforms it applies
    /// to. "Code Sign on Copy" can be optionally enabled for the folder reference.
    case folderReference(path: Path, condition: PlatformCondition? = nil, codeSignOnCopy: Bool = false)

    private enum TypeName: String, Codable, Sendable {
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

extension CopyFileElement: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self = .glob(pattern: .path(value))
    }
}
