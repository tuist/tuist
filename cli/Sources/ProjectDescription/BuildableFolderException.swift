/// Represents exceptions for a buildable folder, such as files to exclude or specific compiler flags to apply.
public struct BuildableFolderException: Sendable, Codable, Equatable, Hashable {
    /// A list of absolute paths to files excluded from the buildable folder.
    public var excluded: [String]

    /// A dictionary mapping files (referenced by their absolute path) to the compiler flags to apply.
    public var compilerFlags: [String: String]

    /// A list of relative paths to headers that should be public (by default they have project access level)
    public var publicHeaders: [String]

    /// A list of relative paths to headers that should be private (by default they have project access level)
    public var privateHeaders: [String]

    /// Creates a new exception for a buildable folder.
    /// - Parameters:
    ///   - exclued: An array of absolute paths to files that should be excluded from the buildable folder.
    ///   - compilerFlags: A dictionary mapping absolute file paths to specific compiler flags to apply to those files.
    ///   - publicHeaders: A list of relative paths to headers that should be public (by dkefault they have project access level)
    ///   - privateHeaders: A list of relative paths to headers that should be private (by default they have project access level)
    private init(excluded: [String], compilerFlags: [String: String], publicHeaders: [String], privateHeaders: [String]) {
        self.excluded = excluded
        self.compilerFlags = compilerFlags
        self.publicHeaders = publicHeaders
        self.privateHeaders = privateHeaders
    }

    /// Creates a new BuildableFolderException using the given excluded files and compiler flags.
    /// - Parameters:
    ///   - excluded: An array of absolute paths to files that should be excluded from the buildable folder.
    ///   - compilerFlags: A dictionary mapping absolute file paths to specific compiler flags to apply to those files.
    public static func exception(
        excluded: [String] = [],
        compilerFlags: [String: String] = [:],
        publicHeaders: [String] = [],
        privateHeaders: [String] = []
    ) -> BuildableFolderException {
        BuildableFolderException(
            excluded: excluded,
            compilerFlags: compilerFlags,
            publicHeaders: publicHeaders,
            privateHeaders: privateHeaders
        )
    }
}
