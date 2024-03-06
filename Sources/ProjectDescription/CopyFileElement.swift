import Foundation

/// A file element from a glob pattern or a folder reference which is conditionally applied to specific platforms.
public enum CopyFileElement: Codable, Equatable {
    /// A file path (or glob pattern) to include with an optional PlatformCondition to control which platforms it applies to.
    case glob(pattern: Path, condition: PlatformCondition? = nil)

    /// A directory path to include as a folder reference with an optional PlatformCondition to control which platforms it applies
    /// to.
    case folderReference(path: Path, condition: PlatformCondition? = nil)

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

extension CopyFileElement: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self = .glob(pattern: .path(value))
    }
}
