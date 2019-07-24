import Foundation

public final class FileGlob: ExpressibleByStringLiteral, Codable {
    /// Relative glob pattern.
    public let glob: String

    /// Initializes a FileGlob instance.
    ///
    /// - Parameters:
    ///   - glob: Relative glob pattern.
    public init(_ glob: String) {
        self.glob = glob
    }

    public convenience init(stringLiteral value: String) {
        self.init(value)
    }
}

public final class FileList: Codable {
    public enum CodingKeys: String, CodingKey {
        case globs
    }

    /// List glob patterns.
    public let globs: [FileGlob]

    /// Initializes the files list with the glob patterns.
    ///
    /// - Parameter globs: Glob patterns.
    public init(globs: [FileGlob]) {
        self.globs = globs
    }

    /// Initializes the files list with the glob patterns as strings.
    ///
    /// - Parameter globs: Glob patterns.
    public init(globs: [String]) {
        self.globs = globs.map(FileGlob.init)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        globs = try container.decode([FileGlob].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(globs)
    }
}

extension FileList: ExpressibleByStringLiteral {
    public convenience init(stringLiteral value: String) {
        self.init(globs: [value])
    }
}

extension FileList: ExpressibleByArrayLiteral {
    public convenience init(arrayLiteral elements: FileGlob...) {
        self.init(globs: elements)
    }
}
