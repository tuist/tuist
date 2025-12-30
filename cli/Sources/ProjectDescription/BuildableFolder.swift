/// A buildable folder (known as synchronized root group in pbxproj's lingo), it's
/// a reference to a folder whose content will be resolved/synced by Xcode. It was
/// introduced by Xcode in the version 16 to reduce frequent git conflicts caused
/// by frequent file reference updates across branches.
public struct BuildableFolder: Sendable, Codable, Equatable, ExpressibleByStringLiteral {
    public var path: Path
    public var exceptions: BuildableFolderExceptions

    /// Creates an instance of a buildable folder.
    /// - Parameter path: Path to the buildable folder.
    /// - Returns: An instance of buildable folder.
    public static func folder(_ path: Path, exceptions: BuildableFolderExceptions = .exceptions([])) -> Self {
        Self(path: path, exceptions: exceptions)
    }

    init(path: Path, exceptions: BuildableFolderExceptions) {
        self.path = path
        self.exceptions = exceptions
    }

    public init(stringLiteral value: String) {
        path = .init(stringLiteral: value)
        exceptions = .exceptions([])
    }
}
