import Foundation

/// A scaffold template model.
public struct Template: Codable, Equatable, Sendable {
    /// Description of template
    public let description: String
    /// Attributes to be passed to template
    public let attributes: [Attribute]
    /// Items to generate
    public let items: [Item]

    public init(
        description: String,
        attributes: [Attribute] = [],
        items: [Item] = []
    ) {
        self.description = description
        self.attributes = attributes
        self.items = items
        dumpIfNeeded(self)
    }

    /// Enum containing information about how to generate item
    public enum Contents: Codable, Equatable, Sendable {
        /// String Contents is defined in `name_of_template.swift` and contains a simple `String`
        /// Can not contain any additional logic apart from plain `String` from `arguments`
        case string(String)
        /// File content is defined in a different file from `name_of_template.swift`
        /// Can contain additional logic and anything that is defined in `ProjectDescriptionHelpers`
        case file(Path)
        /// Directory content is defined in a path
        /// It is just for copying files without modifications and logic inside
        case directory(Path)
    }

    /// File description for generating
    public struct Item: Codable, Equatable, Sendable {
        public let path: String
        public let contents: Contents

        public static func item(path: String, contents: Contents) -> Self {
            self.init(path: path, contents: contents)
        }
    }

    /// Attribute to be passed to `tuist scaffold` for generating with `Template`
    public enum Attribute: Codable, Equatable, Sendable {
        /// Required attribute with a given name
        case required(String)
        /// Optional attribute with a given name and a default value used when attribute not provided by user
        case optional(String, default: Value)
    }
}

extension Template.Attribute {
    /// This represents the default value type of Attribute
    public indirect enum Value: Codable, Equatable, Sendable {
        /// It represents a string value.
        case string(String)
        /// It represents an integer value.
        case integer(Int)
        /// It represents a floating value.
        case real(Double)
        /// It represents a boolean value.
        case boolean(Bool)
        /// It represents a dictionary value.
        case dictionary([String: Value])
        /// It represents an array value.
        case array([Value])
    }
}

extension Template.Attribute.Value: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension Template.Attribute.Value: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .integer(value)
    }
}

extension Template.Attribute.Value: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .real(value)
    }
}

extension Template.Attribute.Value: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .boolean(value)
    }
}

extension Template.Attribute.Value: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, Template.Attribute.Value)...) {
        self = .dictionary(Dictionary(uniqueKeysWithValues: elements))
    }
}

extension Template.Attribute.Value: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Template.Attribute.Value...) {
        self = .array(elements)
    }
}

extension Template.Item {
    /// - Parameters:
    ///     - path: Path where to generate file
    ///     - contents: String Contents
    /// - Returns: `Template.Item` that is `.string`
    public static func string(path: String, contents: String) -> Template.Item {
        Template.Item(path: path, contents: .string(contents))
    }

    /// - Parameters:
    ///     - path: Path where to generate file
    ///     - templatePath: Path of file where the template is defined
    /// - Returns: `Template.Item` that is `.file`
    public static func file(path: String, templatePath: Path) -> Template.Item {
        Template.Item(path: path, contents: .file(templatePath))
    }

    /// - Parameters:
    ///     - path: Path where will be copied the folder
    ///     - sourcePath: Path of folder which will be copied
    /// - Returns: `Template.Item` that is `.directory`
    public static func directory(path: String, sourcePath: Path) -> Template.Item {
        Template.Item(path: path, contents: .directory(sourcePath))
    }
}

extension String.StringInterpolation {
    public mutating func appendInterpolation(_ value: Template.Attribute) {
        switch value {
        case let .required(name), let .optional(name, default: _):
            appendInterpolation("{{ \(name) }}")
        }
    }
}
