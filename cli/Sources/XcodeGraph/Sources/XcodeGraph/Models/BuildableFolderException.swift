import Path

/// Represents exceptions for a buildable folder, such as files to exclude or specific compiler flags to apply.
public struct BuildableFolderException: Sendable, Codable, Equatable, Hashable {
    /// A list of absolute paths to files excluded from the buildable folder.
    public var excluded: [AbsolutePath]

    /// A dictionary mapping files (referenced by their absolute path) to the compiler flags to apply.
    public var compilerFlags: [AbsolutePath: String]

    /// The list of public headers.
    public var publicHeaders: [AbsolutePath]

    /// The list of private headers.
    public var privateHeaders: [AbsolutePath]

    /// A dictionary mapping files (referenced by their absolute path) to the platform condition to apply.
    public var platformFilters: [AbsolutePath: PlatformCondition]

    /// Creates a new exception for a buildable folder.
    /// - Parameters:
    ///   - excluded: An array of absolute paths to files that should be excluded from the buildable folder.
    ///   - compilerFlags: A dictionary mapping absolute file paths to specific compiler flags to apply to those files.
    ///   - publicHeaders: The list of public headers.
    ///   - privateHeaders: The list of private headers.
    ///   - platformFilters: A dictionary mapping absolute file paths to platform conditions.
    public init(
        excluded: [AbsolutePath],
        compilerFlags: [AbsolutePath: String],
        publicHeaders: [AbsolutePath],
        privateHeaders: [AbsolutePath],
        platformFilters: [AbsolutePath: PlatformCondition] = [:]
    ) {
        self.excluded = excluded
        self.compilerFlags = compilerFlags
        self.publicHeaders = publicHeaders
        self.privateHeaders = privateHeaders
        self.platformFilters = platformFilters
    }
}
