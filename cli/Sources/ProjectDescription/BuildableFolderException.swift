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

    /// A dictionary mapping relative file paths within the buildable folder to platform filters.
    /// Use this to restrict specific files to certain platforms (e.g., iOS-only or tvOS-only resources).
    public var platformFilters: [String: Set<PlatformFilter>]

    /// Creates a new exception for a buildable folder.
    /// - Parameters:
    ///   - exclued: An array of absolute paths to files that should be excluded from the buildable folder.
    ///   - compilerFlags: A dictionary mapping absolute file paths to specific compiler flags to apply to those files.
    ///   - publicHeaders: A list of relative paths to headers that should be public (by dkefault they have project access level)
    ///   - privateHeaders: A list of relative paths to headers that should be private (by default they have project access level)
    ///   - platformFilters: A dictionary mapping relative file paths to platform filters.
    private init(
        excluded: [String],
        compilerFlags: [String: String],
        publicHeaders: [String],
        privateHeaders: [String],
        platformFilters: [String: Set<PlatformFilter>]
    ) {
        self.excluded = excluded
        self.compilerFlags = compilerFlags
        self.publicHeaders = publicHeaders
        self.privateHeaders = privateHeaders
        self.platformFilters = platformFilters
    }

    /// Creates a new BuildableFolderException using the given excluded files and compiler flags.
    /// - Parameters:
    ///   - excluded: An array of absolute paths to files that should be excluded from the buildable folder.
    ///   - compilerFlags: A dictionary mapping absolute file paths to specific compiler flags to apply to those files.
    ///   - platformFilters: A dictionary mapping relative file paths within the buildable folder to platform filters.
    public static func exception(
        excluded: [String] = [],
        compilerFlags: [String: String] = [:],
        publicHeaders: [String] = [],
        privateHeaders: [String] = [],
        platformFilters: [String: Set<PlatformFilter>] = [:]
    ) -> BuildableFolderException {
        BuildableFolderException(
            excluded: excluded,
            compilerFlags: compilerFlags,
            publicHeaders: publicHeaders,
            privateHeaders: privateHeaders,
            platformFilters: platformFilters
        )
    }
}
