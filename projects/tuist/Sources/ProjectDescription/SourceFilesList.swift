// MARK: - FileList

/// A model to refer to source files that supports passing compiler flags.
public struct SourceFileGlob: ExpressibleByStringInterpolation, Codable, Equatable {
    /// Relative glob pattern.
    public let glob: Path

    /// Relative glob patterns for excluded files.
    public let excluding: [Path]

    /// Compiler flags.
    public let compilerFlags: String?

    /// Initializes a SourceFileGlob instance.
    ///
    /// - Parameters:
    ///   - glob: Relative glob pattern.
    ///   - excluding: Relative glob patterns for excluded files.
    ///   - compilerFlags: Compiler flags.
    public init(_ glob: Path, excluding: [Path] = [], compilerFlags: String? = nil) {
        self.glob = glob
        self.excluding = excluding
        self.compilerFlags = compilerFlags
    }

    public init(_ glob: Path, excluding: Path?, compilerFlags: String? = nil) {
        let paths: [Path] = excluding.flatMap { [$0] } ?? []
        self.init(glob, excluding: paths, compilerFlags: compilerFlags)
    }

    public init(stringLiteral value: String) {
        self.init(Path(value))
    }
}

public struct SourceFilesList: Codable, Equatable {
    public enum CodingKeys: String, CodingKey {
        case globs
    }

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
        SourceFilesList(globs: paths.map { SourceFileGlob($0) })
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        globs = try container.decode([SourceFileGlob].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(globs)
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
