import Basic

public struct Template {
    public let description: String
    public let attributes: [Attribute]
    public let files: [(path: RelativePath, contents: Contents)]
    public let directories: [RelativePath]

    public init(description: String,
                attributes: [Attribute] = [],
                files: [(path: RelativePath, contents: Contents)] = [],
                directories: [RelativePath] = []) {
        self.description = description
        self.attributes = attributes
        self.files = files
        self.directories = directories
    }

    public enum Attribute {
        case required(String)
        case optional(String, default: String)
        
        public var isOptional: Bool {
            switch self {
            case .required(_):
                return false
            case .optional(_, default: _):
                return true
            }
        }
        
        public var name: String {
            switch self {
            case let .required(name):
                return name
            case let .optional(name, default: _):
                return name
            }
        }
    }

    public enum Contents {
        case `static`(String)
        case generated(AbsolutePath)
    }
}
