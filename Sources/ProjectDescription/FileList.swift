import Foundation

public final class FileList: Codable {
    /// List glob patterns.
    public let globs: [Path]

    /// Initializes the files list with the glob patterns.
    ///
    /// - Parameter globs: Glob patterns.
    public init(globs: [Path]) {
        self.globs = globs
    }
}

extension FileList: ExpressibleByStringLiteral {
    public convenience init(stringLiteral value: String) {
        self.init(globs: [Path(value)])
    }
}

extension FileList: ExpressibleByArrayLiteral {
    public convenience init(arrayLiteral elements: String...) {
        self.init(globs: elements.map { Path($0) })
    }
}
