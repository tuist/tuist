/// Represents exceptions for a buildable folder, such as files to exclude or specific compiler flags to apply.
public struct BuildableFolderException: Sendable, Codable, Equatable, Hashable {
    /// A list of absolute paths to files excluded from the buildable folder.
    public var excluded: [String]

    /// A dictionary mapping files (referenced by their absolute path) to the compiler flags to apply.
    public var compilerFlags: [String: String]

    /// Creates a new exception for a buildable folder.
    /// - Parameters:
    ///   - exclued: An array of absolute paths to files that should be excluded from the buildable folder.
    ///   - compilerFlags: A dictionary mapping absolute file paths to specific compiler flags to apply to those files.
    private init(excluded: [String], compilerFlags: [String: String]) {
        self.excluded = excluded
        self.compilerFlags = compilerFlags
    }

    /// Creates a new BuildableFolderException using the given excluded files and compiler flags.
    /// - Parameters:
    ///   - excluded: An array of absolute paths to files that should be excluded from the buildable folder.
    ///   - compilerFlags: A dictionary mapping absolute file paths to specific compiler flags to apply to those files.
    public static func exception(
        excluded: [String],
        compilerFlags: [String: String] = [:]
    ) -> BuildableFolderException {
        BuildableFolderException(excluded: excluded, compilerFlags: compilerFlags)
    }
}
