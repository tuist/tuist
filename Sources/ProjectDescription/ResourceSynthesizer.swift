import Foundation

/// Resource synthesizer encapsulates how resources with given `extensions` should be synthesized
///
/// For example to synthesize resource accessors for strings, you can use:
/// - `.strings()` for tuist's default
/// - `.strings(plugin: "MyPlugin")` to use strings template from a plugin
/// - `.strings(templatePath: "Templates/Strings.stencil")` to use strings template at a given path
public struct ResourceSynthesizer: Codable, Equatable {
    /// Templates can be of multiple types
    public let templateType: TemplateType
    public let parser: Parser
    public let extensions: Set<String>

    /// Templates can be either a local template file, from a plugin, or a default template from tuist
    public enum TemplateType: Codable, Equatable {
        /// Local template file at a given path
        case file(Path)
        /// Plugin template file
        /// `name` is a name of a plugin
        /// `resourceName` is a name of the resource - that is used for finding a template as well as naming the resulting `.swift` file
        case plugin(name: String, resourceName: String)
        /// Default template defined in tuist
        /// `resourceName` is used for the name of the resulting `.swift` file
        case defaultTemplate(resourceName: String)

        public enum CodingKeys: String, CodingKey {
            case type
            case path
            case name
            case resourceName
        }

        private enum TypeName: String, Codable {
            case file
            case plugin
            case defaultTemplate
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(TypeName.self, forKey: .type)
            switch type {
            case .file:
                let path = try container.decode(Path.self, forKey: .path)
                self = .file(path)
            case .plugin:
                let name = try container.decode(String.self, forKey: .name)
                let resourceName = try container.decode(String.self, forKey: .resourceName)
                self = .plugin(name: name, resourceName: resourceName)
            case .defaultTemplate:
                let resourceName = try container.decode(String.self, forKey: .resourceName)
                self = .defaultTemplate(resourceName: resourceName)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .file(path):
                try container.encode(TypeName.file, forKey: .type)
                try container.encode(path, forKey: .path)
            case let .plugin(name: name, resourceName: resourceName):
                try container.encode(TypeName.plugin, forKey: .type)
                try container.encode(name, forKey: .name)
                try container.encode(resourceName, forKey: .resourceName)
            case let .defaultTemplate(resourceName: resourceName):
                try container.encode(TypeName.defaultTemplate, forKey: .type)
                try container.encode(resourceName, forKey: .resourceName)
            }
        }
    }

    /// There are multiple parsers you can choose from
    /// Each parser will give you different metadata from a file
    /// You can read more about available parsers and how to use their metadata here: https://github.com/SwiftGen/SwiftGen#available-parsers
    public enum Parser: String, Codable {
        case strings
        case assets
        case plists
        case fonts
        case coreData
        case interfaceBuilder
        case json
        case yaml
    }

    /// Default strings synthesizer
    public static func strings() -> Self {
        .strings(templateType: .defaultTemplate(resourceName: "Strings"))
    }

    /// Strings synthesizer defined in a plugin
    public static func strings(plugin: String) -> Self {
        .strings(
            templateType: .plugin(
                name: plugin,
                resourceName: "Strings"
            )
        )
    }

    /// Strings synthesizer with a template defined in `templatePath`
    public static func strings(templatePath: Path) -> Self {
        .strings(templateType: .file(templatePath))
    }

    private static func strings(templateType: TemplateType) -> Self {
        .init(
            templateType: templateType,
            parser: .strings,
            extensions: ["strings", "stringsdict"]
        )
    }

    /// Default assets synthesizer
    public static func assets() -> Self {
        .strings(templateType: .defaultTemplate(resourceName: "Assets"))
    }

    /// Assets synthesizer defined in a plugin
    public static func assets(plugin: String) -> Self {
        .assets(
            templateType: .plugin(
                name: plugin,
                resourceName: "Assets"
            )
        )
    }

    /// Assets synthesizer with a template defined in `templatePath`
    public static func assets(templatePath: Path) -> Self {
        .assets(templateType: .file(templatePath))
    }

    private static func assets(templateType: TemplateType) -> Self {
        .init(
            templateType: templateType,
            parser: .assets,
            extensions: ["xcassets"]
        )
    }

    /// Default fonts synthesizer
    public static func fonts() -> Self {
        .fonts(templateType: .defaultTemplate(resourceName: "Fonts"))
    }

    /// Fonts synthesizer defined in a plugin
    public static func fonts(plugin: String) -> Self {
        .fonts(
            templateType: .plugin(
                name: plugin,
                resourceName: "Fonts"
            )
        )
    }

    /// Fonts synthesizer with a template defined in `templatePath`
    public static func fonts(templatePath: Path) -> Self {
        .fonts(templateType: .file(templatePath))
    }

    private static func fonts(templateType: TemplateType) -> Self {
        .init(
            templateType: templateType,
            parser: .fonts,
            extensions: ["otf", "ttc", "ttf"]
        )
    }

    /// Default plists synthesizer
    public static func plists() -> Self {
        .plists(templateType: .defaultTemplate(resourceName: "Plists"))
    }

    /// Plists synthesizer defined in a plugin
    public static func plists(plugin: String) -> Self {
        .plists(
            templateType: .plugin(
                name: plugin,
                resourceName: "Plists"
            )
        )
    }

    /// Plists synthesizer with a template defined in `templatePath`
    public static func plists(templatePath: Path) -> Self {
        .plists(templateType: .file(templatePath))
    }

    private static func plists(templateType: TemplateType) -> Self {
        .init(
            templateType: templateType,
            parser: .plists,
            extensions: ["plist"]
        )
    }

    /// CoreData synthesizer defined in a plugin
    public static func coreData(plugin: String) -> Self {
        .coreData(
            templateType: .plugin(
                name: plugin,
                resourceName: "CoreData"
            )
        )
    }

    /// CoreData synthesizer with a template defined in `templatePath`
    public static func coreData(templatePath: Path) -> Self {
        .coreData(templateType: .file(templatePath))
    }

    private static func coreData(templateType: TemplateType) -> Self {
        .init(
            templateType: templateType,
            parser: .coreData,
            extensions: ["xcdatamodeld"]
        )
    }

    /// InterfaceBuilder synthesizer defined in a plugin
    public static func interfaceBuilder(plugin: String) -> Self {
        .interfaceBuilder(
            templateType: .plugin(
                name: plugin,
                resourceName: "InterfaceBuilder"
            )
        )
    }

    /// InterfaceBuilder synthesizer with a template defined in `templatePath`
    public static func interfaceBuilder(templatePath: Path) -> Self {
        .interfaceBuilder(templateType: .file(templatePath))
    }

    private static func interfaceBuilder(templateType: TemplateType) -> Self {
        .init(
            templateType: templateType,
            parser: .interfaceBuilder,
            extensions: ["storyboard"]
        )
    }

    /// JSON synthesizer defined in a plugin
    public static func json(plugin: String) -> Self {
        .coreData(
            templateType: .plugin(
                name: plugin,
                resourceName: "JSON"
            )
        )
    }

    /// JSON synthesizer with a template defined in `templatePath`
    public static func json(templatePath: Path) -> Self {
        .json(templateType: .file(templatePath))
    }

    private static func json(templateType: TemplateType) -> Self {
        .init(
            templateType: templateType,
            parser: .json,
            extensions: ["json"]
        )
    }

    /// YAML synthesizer defined in a plugin
    public static func yaml(plugin: String) -> Self {
        .yaml(
            templateType: .plugin(
                name: plugin,
                resourceName: "YAML"
            )
        )
    }

    /// CoreData synthesizer with a template defined in `templatePath`
    public static func yaml(templatePath: Path) -> Self {
        .yaml(templateType: .file(templatePath))
    }

    private static func yaml(templateType: TemplateType) -> Self {
        .init(
            templateType: templateType,
            parser: .yaml,
            extensions: ["yml"]
        )
    }

    /// Custom synthesizer from a plugin
    /// - Parameters:
    ///     - plugin: Name of a plugin where resource synthesizer template is located
    ///     - parser: `Parser` to use for parsing the file to obtain its data
    ///     - extensions: Set of extensions that should be parsed
    ///     - resourceName: Name of the template file and the resulting `.swift` file
    public static func custom(
        plugin: String,
        parser: Parser,
        extensions: Set<String>,
        resourceName: String
    ) -> Self {
        .init(
            templateType: .plugin(name: plugin, resourceName: resourceName),
            parser: parser,
            extensions: extensions
        )
    }

    /// Custom local synthesizer
    /// - Parameters:
    ///     - path: Path to the template
    ///     - parser: `Parser` to use for parsing the file to obtain its data
    ///     - extensions: Set of extensions that should be parsed
    public static func custom(
        path: Path,
        parser: Parser,
        extensions: Set<String>
    ) -> Self {
        .init(
            templateType: .file(path),
            parser: parser,
            extensions: extensions
        )
    }
}

extension Array where Element == ResourceSynthesizer {
    public static var `default`: Self {
        [
            .strings(),
            .assets(),
            .plists(),
            .fonts(),
        ]
    }
}
