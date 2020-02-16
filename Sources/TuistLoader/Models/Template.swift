import Basic

public struct Template {
    public let description: String
    public let files: [(path: RelativePath, contents: String)]
    public let directories: [RelativePath]
}
