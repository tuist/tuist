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

    /// The name of a target, other than the folder's owning target, that the `included` files should be members of.
    /// When `nil` the exception applies to the owning target and `excluded` files are removed from it. When set, the
    /// `included` files are added to that target instead, mapping to a `PBXFileSystemSynchronizedBuildFileExceptionSet`
    /// whose `target` is the foreign target.
    public var target: String?

    /// A list of absolute paths, within the buildable folder, of files to add to `target`. Only meaningful when
    /// `target` is set.
    public var included: [AbsolutePath]

    /// Creates a new exception for a buildable folder.
    /// - Parameters:
    ///   - excluded: An array of absolute paths to files that should be excluded from the buildable folder.
    ///   - compilerFlags: A dictionary mapping absolute file paths to specific compiler flags to apply to those files.
    ///   - publicHeaders: The list of public headers.
    ///   - privateHeaders: The list of private headers.
    ///   - platformFilters: A dictionary mapping absolute file paths to platform conditions.
    ///   - target: The name of the foreign target the `included` files are added to, or `nil` for the owning target.
    ///   - included: Absolute paths, within the buildable folder, of files to add to `target`.
    public init(
        excluded: [AbsolutePath],
        compilerFlags: [AbsolutePath: String],
        publicHeaders: [AbsolutePath],
        privateHeaders: [AbsolutePath],
        platformFilters: [AbsolutePath: PlatformCondition] = [:],
        target: String? = nil,
        included: [AbsolutePath] = []
    ) {
        self.excluded = excluded
        self.compilerFlags = compilerFlags
        self.publicHeaders = publicHeaders
        self.privateHeaders = privateHeaders
        self.platformFilters = platformFilters
        self.target = target
        self.included = included
    }
}
