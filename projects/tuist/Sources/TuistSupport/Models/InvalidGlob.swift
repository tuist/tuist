import TSCBasic

/// A structs that represents an invalid glob pattern.
public struct InvalidGlob: Equatable, CustomStringConvertible {
    /// Glob patterns.
    public let pattern: String

    /// Path to a non existing directory.
    public let nonExistentPath: AbsolutePath

    public init(pattern: String, nonExistentPath: AbsolutePath) {
        self.pattern = pattern
        self.nonExistentPath = nonExistentPath
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        "The directory \"\(nonExistentPath)\" defined in the glob pattern \"\(pattern)\" does not exist."
    }
}

extension Array where Element == InvalidGlob {
    public var invalidGlobsDescription: String {
        map { "- " + String(describing: $0) }.joined(separator: "\n")
    }
}
