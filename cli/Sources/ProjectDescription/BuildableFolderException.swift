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

    /// The name of a target, other than the folder's owning target, that the `included` files should be members of.
    /// When `nil` (the default) the exception applies to the folder's owning target and `excluded` files are removed
    /// from it. When set, the `included` files are added to that target instead.
    public var target: String?

    /// A list of relative paths, within the buildable folder, of files to add to `target`. Only meaningful when
    /// `target` is set.
    public var included: [String]

    private init(
        excluded: [String],
        compilerFlags: [String: String],
        publicHeaders: [String],
        privateHeaders: [String],
        platformFilters: [String: Set<PlatformFilter>],
        target: String?,
        included: [String]
    ) {
        self.excluded = excluded
        self.compilerFlags = compilerFlags
        self.publicHeaders = publicHeaders
        self.privateHeaders = privateHeaders
        self.platformFilters = platformFilters
        self.target = target
        self.included = included
    }

    /// Creates a new BuildableFolderException using the given excluded files and compiler flags.
    /// - Parameters:
    ///   - excluded: An array of absolute paths to files that should be excluded from the buildable folder.
    ///   - compilerFlags: A dictionary mapping absolute file paths to specific compiler flags to apply to those files.
    ///   - publicHeaders: A list of relative paths to headers that should be public (by default they have project access level)
    ///   - privateHeaders: A list of relative paths to headers that should be private (by default they have project access level)
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
            platformFilters: platformFilters,
            target: nil,
            included: []
        )
    }

    /// Creates a new BuildableFolderException that adds files living inside this buildable folder to another target.
    ///
    /// Xcode 16 lets a file inside one target's buildable folder be a member of a different target. Use this to express
    /// "also compile/copy these files into `target`" without an explicit `sources:`/`resources:` glob, which would
    /// otherwise materialise a duplicate flat file reference at the project root.
    ///
    /// - Parameters:
    ///   - target: The name of the target the `included` files should be added to.
    ///   - included: Relative paths, within the buildable folder, of the files to add to `target`.
    ///   - compilerFlags: A dictionary mapping relative file paths within the buildable folder to compiler flags.
    ///   - platformFilters: A dictionary mapping relative file paths within the buildable folder to platform filters.
    public static func exception(
        target: String,
        included: [String] = [],
        compilerFlags: [String: String] = [:],
        platformFilters: [String: Set<PlatformFilter>] = [:]
    ) -> BuildableFolderException {
        BuildableFolderException(
            excluded: [],
            compilerFlags: compilerFlags,
            publicHeaders: [],
            privateHeaders: [],
            platformFilters: platformFilters,
            target: target,
            included: included
        )
    }
}
