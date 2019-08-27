import Foundation

public final class FileList: Codable {
    /// List glob patterns.
    public let globs: [String]

    /// Initializes the files list with the glob patterns.
    ///
    /// - Parameter globs: Glob patterns.
    public init(globs: [String]) {
        self.globs = globs
    }
}

extension FileList: ExpressibleByStringLiteral {
    public convenience init(stringLiteral value: String) {
        self.init(globs: [value])
    }
}

extension FileList: ExpressibleByArrayLiteral {
    public convenience init(arrayLiteral elements: String...) {
        self.init(globs: elements)
    }
}
