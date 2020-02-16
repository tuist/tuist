public struct Template: Codable {
    public let description: String
    public let files: [File]
    public let directories: [String]
    
    public init(description: String,
                files: [File] = [],
                directories: [String] = []) {
        self.description = description
        self.files = files
        self.directories = directories
        dumpIfNeeded(self)
    }
}

public struct File: Codable {
    public let path: String
    public let contents: String
    
    public init(path: String, contents: String) {
        self.path = path
        self.contents = contents
    }
}
