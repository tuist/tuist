
// MARK: - FileList

public final class FileList: Codable {
    public enum CodingKeys: String, CodingKey {
        case globs
    }

    public let globs: [String]

    public init(globs: [String]) {
        self.globs = globs
    }
}

/// Support file as single string
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
