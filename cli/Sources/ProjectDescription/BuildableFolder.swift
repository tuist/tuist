/// A buildable folder (known as synchronized root group in pbxproj's lingo), it's
/// a reference to a folder whose content will be resolved/synced by Xcode. It was
/// introduced by Xcode in the version 16 to reduce frequent git conflicts caused
/// by frequent file reference updates across branches.
public struct BuildableFolder: Sendable, Codable, Equatable, ExpressibleByStringLiteral {
    public var path: Path

    /// Creates an instance of a buildable folder.
    /// - Parameter path: Path to the buildable folder.
    /// - Returns: An instance of buildable folder.
    public static func folder(path: Path) -> Self {
        Self(path: path)
    }

    init(path: Path) {
        self.path = path
    }

    public init(stringLiteral value: String) {
        path = .init(stringLiteral: value)
    }
}
