// MARK: - FileList

public typealias FileList = SourceFilesList

/// A model to refer to source files that supports passing compiler flags.
public final class SourceFileGlob: ExpressibleByStringLiteral, Codable {
    /// Relative glob pattern.
    public let glob: String

    /// Compiler flags.
    public let compilerFlags: String?

    /// Initializes a SourceFileGlob instance.
    ///
    /// - Parameters:
    ///   - glob: Relative glob pattern.
    ///   - compilerFlags: Compiler flags.
    public init(_ glob: String, compilerFlags: String? = nil) {
        self.glob = glob
        self.compilerFlags = compilerFlags
    }

    public convenience init(stringLiteral value: String) {
        self.init(value)
    }
}

public final class SourceFilesList: Codable {
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
extension FileList: ExpressibleByStringLiteral {
    public convenience init(stringLiteral value: String) {
        self.init(globs: [value])
    }
}

extension FileList: ExpressibleByArrayLiteral {
    public convenience init(arrayLiteral elements: SourceFileGlob...) {
        self.init(globs: elements)
    }
}
