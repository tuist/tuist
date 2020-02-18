import Basic

public struct Template {
    public let description: String
    public let attributes: [Attribute]
    public let files: [(path: RelativePath, contents: String)]
    public let directories: [RelativePath]
    
    public init(description: String,
                attributes: [Attribute],
                files: [(path: RelativePath, contents: String)],
                directories: [RelativePath]) {
        self.description = description
        self.attributes = attributes
        self.files = files
        self.directories = directories
    }
    
    public enum Attribute {
        case required(String)
        case optional(String, default: String)
    }
}
