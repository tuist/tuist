public struct Template: Codable {
    public let description: String
    public let arguments: [Argument]
    public let files: [File]
    public let directories: [String]
    
    public init(description: String,
                arguments: [Argument] = [],
                files: [File] = [],
                directories: [String] = []) {
        self.description = description
        self.arguments = arguments
        self.files = files
        self.directories = directories
        dumpIfNeeded(self)
    }
}

public extension String.StringInterpolation {
    mutating func appendInterpolation(_ value: Argument) {
        switch value {
        case let .required(name):
            appendInterpolation("{{ \(name) }}")
        case let .optional(name, default: defaultValue):
            appendInterpolation("{{ \(name) ?? \(defaultValue) }}")
        }
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

public enum Argument: Codable {
    case required(String)
    case optional(String, default: String)
    
    enum CodingKeys: String, CodingKey {
        case type
        case name
        case `default`
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let type = try container.decode(String.self, forKey: .type)
        if type == "required" {
            self = .required(name)
        } else if type == "optional" {
            let defaultValue = try container.decode(String.self, forKey: .default)
            self = .optional(name, default: defaultValue)
        } else {
            fatalError("Argument '\(type)' not supported")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .required(name):
            try container.encode("required", forKey: .type)
            try container.encode(name, forKey: .name)
        case let .optional(name, default: defaultValue):
            try container.encode("optional", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(defaultValue, forKey: .default)
        }
    }
}

