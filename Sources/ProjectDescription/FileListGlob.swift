import Foundation

/// A type that represents a list of source files defined by a glob.
public struct FileListGlob: Codable, Equatable {
    /// Glob pattern to header files
    public var glob: Path
    
    /// Relative glob patterns for excluded files.
    public var excluding: [Path]
    
    /// Generage the file glob.
    /// - Parameters:
    ///   - glob: Glob pattern to files
    ///   - excluding: Glob pattern used for filtering out files.
    public static func glob(_ glob: Path,
                            excluding: [Path] = []) -> FileListGlob {
        .init(glob, excluding: excluding)
    }
    
    /// Initializes the file glob.
    /// - Parameters:
    ///   - glob: Glob pattern to files
    ///   - excluding: Glob pattern used for filtering out files.
    private init(_ glob: Path,
                 excluding: [Path] = []) {
        self.glob = glob
        self.excluding = excluding
    }
    
    public static func glob(_ glob: Path,
                            excluding: Path?) -> FileListGlob {
        .init(glob, excluding: nil)
    }
    
    private init(_ glob: Path,
                 excluding: Path?) {
        let paths: [Path] = excluding.flatMap { [$0] } ?? []
        self.init(glob, excluding: paths)
    }
}

extension FileListGlob: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self.init(Path(value))
    }
}
