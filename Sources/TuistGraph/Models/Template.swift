import TSCBasic

public struct Template: Equatable {
    public let description: String
    public let attributes: [Attribute]
    public let items: [Item]

    public init(
        description: String,
        attributes: [Attribute] = [],
        items: [Item] = []
    ) {
        self.description = description
        self.attributes = attributes
        self.items = items
    }

    public enum Attribute: Equatable {
        case required(String)
        case optional(String, default: String)

        public var isOptional: Bool {
            switch self {
            case .required:
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

    public enum Contents: Equatable {
        case string(String)
        case file(AbsolutePath)
        case directory(AbsolutePath)
    }

    public struct Item: Equatable {
        public let path: RelativePath
        public let contents: Contents

        public init(
            path: RelativePath,
            contents: Contents
        ) {
            self.path = path
            self.contents = contents
        }
    }
}
