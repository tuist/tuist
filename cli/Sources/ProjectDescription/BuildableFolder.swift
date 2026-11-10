/// A buildable folder (known as synchronized root group in pbxproj's lingo), it's
/// a reference to a folder whose content will be resolved/synced by Xcode. It was
/// introduced by Xcode in the version 16 to reduce frequent git conflicts caused
/// by frequent file reference updates across branches.
public struct BuildableFolder: Sendable, Codable, Equatable, ExpressibleByStringLiteral {
    public var path: Path
    public var exceptions: BuildableFolderExceptions
    public var optional: Bool
    public var contents: Set<BuildableFolderContent>?

    /// Creates an instance of a buildable folder.
    ///
    /// Tuist looks at a buildable folder's files to decide, among other things, whether the target needs a Sources
    /// phase and whether it needs a resource bundle. When the files only appear after `tuist generate` (for example,
    /// a build phase script or a tool like SwiftGen, Sourcery or protoc writes them), declare `contents` so those
    /// decisions don't depend on what is on disk when you generate:
    ///
    /// ```swift
    /// .target(
    ///     name: "Networking",
    ///     destinations: .iOS,
    ///     product: .staticFramework,
    ///     bundleId: "dev.tuist.Networking",
    ///     buildableFolders: [
    ///         "Sources",
    ///         .folder("Generated", contents: [.sources, .resources]),
    ///     ]
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - path: Path to the buildable folder.
    ///   - exceptions: Files or directories to exclude, or per-file build settings overrides.
    ///   - optional: When `true`, the folder generation skipped with a warning if it does not exist. Defaults to `false`.
    ///     It has no effect when `contents` is declared: a folder with declared contents is never skipped.
    ///   - contents: What the folder will contain. When `nil` (the default), Tuist scans the folder's files at
    ///     generation time. When declared, Tuist ignores the files on disk, so the generated project is the same before
    ///     and after the folder is filled, and creates the folder if it doesn't exist.
    /// - Returns: An instance of buildable folder.
    public static func folder(
        _ path: Path,
        exceptions: BuildableFolderExceptions = .exceptions([]),
        optional: Bool = false,
        contents: Set<BuildableFolderContent>? = nil
    ) -> Self {
        Self(path: path, exceptions: exceptions, optional: optional, contents: contents)
    }

    init(
        path: Path,
        exceptions: BuildableFolderExceptions,
        optional: Bool = false,
        contents: Set<BuildableFolderContent>? = nil
    ) {
        self.path = path
        self.exceptions = exceptions
        self.optional = optional
        self.contents = contents
    }

    public init(stringLiteral value: String) {
        path = .init(stringLiteral: value)
        exceptions = .exceptions([])
        optional = false
        contents = nil
    }
}

/// The kinds of files a buildable folder declares it will contain.
public enum BuildableFolderContent: String, Sendable, Codable, Hashable {
    /// Files Xcode compiles, such as Swift, Objective-C or C files and headers.
    ///
    /// Tuist treats them as Swift sources when it decides whether to generate the `Bundle.module` accessor, and as
    /// possibly containing headers when it decides whether the target needs a Headers phase. Resource accessors that
    /// Tuist synthesizes from file contents (for example, for asset catalogs) aren't generated for a folder that
    /// declares its contents.
    case sources

    /// Files Xcode copies into the product, such as images, string catalogs or JSON files.
    ///
    /// In a static target, Tuist moves them to the companion resource bundle it generates for the target. A folder that
    /// also declares `.sources` is added to both targets, and build settings route its files by type: up to four
    /// directory levels deep, resources are only copied into the bundle; deeper ones are also copied into the static
    /// target.
    case resources
}
