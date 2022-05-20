import Foundation

/// A scaffold template model.
public struct Template: Codable, Equatable {
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
