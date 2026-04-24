/// A buildable folder (known as synchronized root group in pbxproj's lingo), it's
/// a reference to a folder whose content will be resolved/synced by Xcode. It was
/// introduced by Xcode in the version 16 to reduce frequent git conflicts caused
/// by frequent file reference updates across branches.
public struct BuildableFolder: Sendable, Codable, Equatable, ExpressibleByStringLiteral {
    public var path: Path
    public var exceptions: BuildableFolderExceptions
    public var optional: Bool

    /// Creates an instance of a buildable folder.
    /// - Parameters:
    ///   - path: Path to the buildable folder.
    ///   - exceptions: Files or directories to exclude, or per-file build settings overrides.
    ///   - optional: When `true`, the folder generation skipped with a warning if it does not exist. Defaults to `false`.
    /// - Returns: An instance of buildable folder.
    public static func folder(
        _ path: Path,
        exceptions: BuildableFolderExceptions = .exceptions([]),
        optional: Bool = false
    ) -> Self {
        Self(path: path, exceptions: exceptions, optional: optional)
    }

    init(path: Path, exceptions: BuildableFolderExceptions, optional: Bool = false) {
        self.path = path
        self.exceptions = exceptions
        self.optional = optional
    }

    public init(stringLiteral value: String) {
        path = .init(stringLiteral: value)
        exceptions = .exceptions([])
        optional = false
    }
}
