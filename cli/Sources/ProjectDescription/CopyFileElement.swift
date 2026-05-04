/// A file element from a glob pattern, a folder reference, or a build product which is conditionally
/// applied to specific platforms with an optional "Code Sign On Copy" flag.
public enum CopyFileElement: Codable, Equatable, Sendable, ExpressibleByStringInterpolation {
    /// A file path (or glob pattern) to include with an optional PlatformCondition to control which platforms it applies.
    /// "Code Sign on Copy" can be optionally enabled for the glob.
    case glob(pattern: Path, condition: PlatformCondition? = nil, codeSignOnCopy: Bool = false)

    /// A directory path to include as a folder reference with an optional PlatformCondition to control which platforms it applies
    /// to. "Code Sign on Copy" can be optionally enabled for the folder reference.
    case folderReference(path: Path, condition: PlatformCondition? = nil, codeSignOnCopy: Bool = false)

    /// A reference to a dependent target's build product (e.g. a helper `.app` for Login Items embedding).
    /// The product is resolved from `BUILT_PRODUCTS_DIR` during the build, not from the filesystem at generation time.
    case buildProduct(name: String, condition: PlatformCondition? = nil, codeSignOnCopy: Bool = false)

    private enum TypeName: String, Codable {
        case glob
        case folderReference
        case buildProduct
    }

    private var typeName: TypeName {
        switch self {
        case .glob:
            return .glob
        case .folderReference:
            return .folderReference
        case .buildProduct:
            return .buildProduct
        }
    }

    public init(stringLiteral value: String) {
        self = .glob(pattern: .path(value))
    }
}
