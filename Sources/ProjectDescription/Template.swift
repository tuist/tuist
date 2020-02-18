import Foundation

/// Template manifest - used with `tuist scaffold`
public struct Template: Codable {
    /// Description of template
    public let description: String
    /// Attributes to be passed to template
    public let attributes: [Attribute]
    /// Files to generate
    public let files: [File]
    /// Directories to generate
    public let directories: [String]
    
    public init(description: String,
                arguments: [Attribute] = [],
                files: [File] = [],
                directories: [String] = []) {
        self.description = description
        self.attributes = arguments
        self.files = files
        self.directories = directories
        dumpIfNeeded(self)
    }
    
    /// File description for generating
    public struct File: Codable {
        public let path: String
        public let contents: String
        
        public init(path: String, contents: String) {
            self.path = path
            self.contents = contents
        }
    }
    
    /// Attribute to be passed to `tuist scaffold` for generating with `Template`
    public enum Attribute: Codable {
        /// Required attribute with a given name
        case required(String)
        /// Optional attribute with a given name and a default value used when attribute not provided by user
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
}

public extension String.StringInterpolation {
    mutating func appendInterpolation(_ value: Template.Attribute) {
        switch value {
        case let .required(name), let .optional(name, default: _):
            appendInterpolation("{{ \(name) }}")
        }
    }
}
