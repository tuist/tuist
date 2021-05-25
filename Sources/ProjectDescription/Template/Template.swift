import Foundation

/// Template manifest - used with `tuist scaffold`
public struct Template: Codable, Equatable {
    /// Description of template
    public let description: String
    /// Attributes to be passed to template
    public let attributes: [Attribute]
    /// Items to generate
    public let items: [Item]

    public init(description: String,
                attributes: [Attribute] = [],
                items: [Item] = [])
    {
        self.description = description
        self.attributes = attributes
        self.items = items
        dumpIfNeeded(self)
    }

    @available(*, deprecated, message: "Use init with `items: [Item]` instead")
    public init(description: String,
                attributes: [Attribute] = [],
                files: [Item] = [])
    {
        self.description = description
        self.attributes = attributes
        items = files
        dumpIfNeeded(self)
    }

    /// Enum containing information about how to generate item
    public enum Contents: Codable, Equatable {
        /// String Contents is defined in `name_of_template.swift` and contains a simple `String`
        /// Can not contain any additional logic apart from plain `String` from `arguments`
        case string(String)
        /// File content is defined in a different file from `name_of_template.swift`
        /// Can contain additional logic and anything that is defined in `ProjectDescriptionHelpers`
        case file(Path)
        /// Directory content is defined in a path
        /// It is just for copying files without modifications and logic inside
        case directory(Path)

        private enum CodingKeys: String, CodingKey {
            case type
            case value
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            if type == "string" {
                let value = try container.decode(String.self, forKey: .value)
                self = .string(value)
            } else if type == "file" {
                let value = try container.decode(Path.self, forKey: .value)
                self = .file(value)
            } else if type == "directory" {
                let value = try container.decode(Path.self, forKey: .value)
                self = .directory(value)
            } else {
                fatalError("Argument '\(type)' not supported")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case let .string(contents):
                try container.encode("string", forKey: .type)
                try container.encode(contents, forKey: .value)
            case let .file(path):
                try container.encode("file", forKey: .type)
                try container.encode(path, forKey: .value)
            case let .directory(path):
                try container.encode("directory", forKey: .type)
                try container.encode(path, forKey: .value)
            }
        }
    }

    /// File description for generating
    public struct Item: Codable, Equatable {
        public let path: String
        public let contents: Contents

        public init(path: String, contents: Contents) {
            self.path = path
            self.contents = contents
        }
    }

    /// Attribute to be passed to `tuist scaffold` for generating with `Template`
    public enum Attribute: Codable, Equatable {
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

public extension Template.Item {
    /// - Parameters:
    ///     - path: Path where to generate file
    ///     - contents: String Contents
    /// - Returns: `Template.Item` that is `.string`
    static func string(path: String, contents: String) -> Template.Item {
        Template.Item(path: path, contents: .string(contents))
    }

    /// - Parameters:
    ///     - path: Path where to generate file
    ///     - templatePath: Path of file where the template is defined
    /// - Returns: `Template.Item` that is `.file`
    static func file(path: String, templatePath: Path) -> Template.Item {
        Template.Item(path: path, contents: .file(templatePath))
    }

    /// - Parameters:
    ///     - path: Path where will be copied the folder
    ///     - sourcePath: Path of folder which will be copied
    /// - Returns: `Template.Item` that is `.directory`
    static func directory(path: String, sourcePath: Path) -> Template.Item {
        Template.Item(path: path, contents: .directory(sourcePath))
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
