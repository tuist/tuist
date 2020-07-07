import TSCBasic

public struct InvalidGlob {
    public let pattern: String
    public let nonExistentPath: AbsolutePath

    public init(pattern: String, nonExistentPath: AbsolutePath) {
        self.pattern = pattern
        self.nonExistentPath = nonExistentPath
    }
}

extension InvalidGlob: CustomStringConvertible {
    public var description: String {
        "The directory \(nonExistentPath), defined in glob pattern: \"\(pattern)\", does not exist."
    }
}

extension Array where Element == InvalidGlob {
    public var invalidGlobsDescription: String {
        map { "\t- " + String(describing: $0) }.joined(separator: "\n")
    }
}
