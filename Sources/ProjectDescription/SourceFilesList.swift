import Foundation

/// A glob pattern configuration representing source files and its compiler flags, if any.
public struct SourceFileGlob: Codable, Equatable {
    /// Glob pattern to the source files.
    public let glob: Path

    /// Glob patterns for source files that will be excluded.
    public let excluding: [Path]

    /// The compiler flags to be set to the source files in the sources build phase.
    public let compilerFlags: String?

    /// The source file attribute to be set in the build phase.
    public let codeGen: FileCodeGen?

    /// Returns a source glob pattern configuration.
    ///
    /// - Parameters:
    ///   - glob: Glob pattern to the source files.
    ///   - excluding: Glob patterns for source files that will be excluded.
    ///   - compilerFlags: The compiler flags to be set to the source files in the sources build phase.
    ///   - codeGen: The source file attribute to be set in the build phase.
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

/// A collection of source file globs.
public struct SourceFilesList: Codable, Equatable {
    /// List glob patterns.
    public let globs: [SourceFileGlob]

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
        self.globs = globs.map(SourceFileGlob.init)
    }

    /// Returns a sources list from a list of paths.
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
