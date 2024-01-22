import Foundation

/// A glob pattern configuration representing source files and its compiler flags, if any.
public struct SourceFileGlob: Codable, Equatable {
    /// Glob pattern to the source files.
    public var glob: Path

    /// Glob patterns for source files that will be excluded.
    public var excluding: [Path] = []

    /// The compiler flags to be set to the source files in the sources build phase.
    public var compilerFlags: String? = nil

    /// The source file attribute to be set in the build phase.
    public var codeGen: FileCodeGen? = nil

    /// Source file condition for compilation
    public var compilationCondition: PlatformCondition? = nil
}

extension SourceFileGlob: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self.init(glob: Path(value), excluding: [], compilerFlags: nil, codeGen: nil, compilationCondition: nil)
    }
}

/// A collection of source file globs.
public struct SourceFilesList: Codable, Equatable {
    /// List glob patterns.
    public var globs: [SourceFileGlob]

    /// Creates the source files list with the glob patterns.
    ///
    /// - Parameter globs: Glob patterns.
    public init(globs: [SourceFileGlob]) {
        self.globs = globs
    }

    /// Creates the source files list with the glob patterns as strings.
    ///
    /// - Parameter globs: Glob patterns.
    public init(globs: [String]) {
        self.init(globs: globs.map(SourceFileGlob.init))
    }

    /// Returns a sources list from a list of paths.
    /// - Parameter paths: Source paths.
    public init(paths: [Path]) -> SourceFilesList {
        self.init(globs: paths.map { .glob($0) })
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
