import Foundation

public struct FileList: Codable, Equatable {
    /// List glob patterns.
    public let globs: [FileListGlob]

    /// Initializes the files list with the glob patterns.
    ///
    ///   - glob: Relative glob pattern.
    ///   - excluding: Relative glob patterns for excluded files.
    public static func list(_ globs: [FileListGlob]) -> FileList {
        .init(globs)
    }

    /// Initializes the files list with the glob patterns.
    ///
    ///   - glob: Relative glob pattern.
    ///   - excluding: Relative glob patterns for excluded files.
    private init(_ globs: [FileListGlob]) {
        self.globs = globs
    }

    // for backward compatibility when globs property had [Path] type
    public init(globs: [Path]) {
        self.init(globs.map { .glob($0) })
    }

    public enum CodingKeys: String, CodingKey {
        case globs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // previously globs property had [Path] type
        if let paths = try? container.decode([Path].self, forKey: .globs) {
            self.init(globs: paths)
        } else {
            let globs = try container.decode([FileListGlob].self, forKey: .globs)
            self.init(globs)
        }
    }
}

extension FileList: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self.init(globs: [.init(stringLiteral: value)])
    }
}

extension FileList: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: String...) {
        self.init(elements.map { .init(stringLiteral: $0) })
    }
}
