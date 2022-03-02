// MARK: - FileList

/// It represents a glob pattern that refers to source files and the compiler flags (if any) to be set in the build phase:
public struct SourceFileGlob: Codable, Equatable {
    /// Glob pattern to the source files.
    public let glob: Path

    /// Glob patterns for source files that will be excluded.
    public let excluding: [Path]

    /// The compiler flags to be set to the source files in the sources build phase.
    public let compilerFlags: String?

    /// The source file attribute to be set in the build phase.
    public let codeGen: FileCodeGen?

    /// Initializes a SourceFileGlob instance.
    ///
    /// - Parameters:
    ///   - glob: Glob pattern to the source files.
    ///   - excluding: Glob patterns for source files that will be excluded.
    ///   - compilerFlags: The compiler flags to be set to the source files in the sources build phase.
    ///   - codegen: The source file attribute to be set in the build phase.
    public static func glob(
        _ glob: Path,
        excluding: [Path] = [],
        compilerFlags: String? = nil,
        codeGen: FileCodeGen? = nil
    ) -> Self {
        .init(glob: glob, excluding: excluding, compilerFlags: compilerFlags, codeGen: codeGen)
    }

    public static func glob(
        _ glob: Path,
        excluding: Path?,
        compilerFlags: String? = nil,
        codeGen: FileCodeGen? = nil
    ) -> Self {
        let paths: [Path] = excluding.flatMap { [$0] } ?? []
        return .init(glob: glob, excluding: paths, compilerFlags: compilerFlags, codeGen: codeGen)
    }
}

extension SourceFileGlob: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self.init(glob: Path(value), excluding: [], compilerFlags: nil, codeGen: nil)
    }
}

/// It represents a list of source files that are part of a target:
public struct SourceFilesList: Codable, Equatable {
    /// List glob patterns.
    public let globs: [SourceFileGlob]

    /// Initializes the source files list with the glob patterns.
    ///
    /// - Parameter globs: Glob patterns.
    public init(globs: [SourceFileGlob]) {
        self.globs = globs
    }

    /// Initializes the source files list with the glob patterns as strings.
    ///
    /// - Parameter globs: Glob patterns.
    public init(globs: [String]) {
        self.globs = globs.map(SourceFileGlob.init)
    }

    /// Initializes a sources list with a list of paths.
    /// - Parameter paths: Source paths.
    public static func paths(_ paths: [Path]) -> SourceFilesList {
        SourceFilesList(globs: paths.map { .glob($0) })
    }
}

/// Support file as single string
extension SourceFilesList: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self.init(globs: [value])
    }
}

extension SourceFilesList: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: SourceFileGlob...) {
        self.init(globs: elements)
    }
}
