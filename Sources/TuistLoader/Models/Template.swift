import Basic

public struct Template {
    public let description: String
    public let attributes: [Attribute]
    public let files: [(path: RelativePath, contents: String)]
    public let directories: [RelativePath]
}

public enum Attribute {
    case required(String)
    case optional(String, default: String)
}
