import Foundation

/// A resource synthesizer for given file extensions.
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
        /// Plugin template file
        /// `name` is a name of a plugin
        /// `resourceName` is a name of the resource - that is used for finding a template as well as naming the resulting `.swift` file
        case plugin(name: String, resourceName: String)
        /// Default template defined `Tuist/{ProjectName}`, or if not present there, in tuist itself
        /// `resourceName` is used for the name of the resulting `.swift` file
        case defaultTemplate(resourceName: String)
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
        case files
    }

    /// Default strings synthesizer defined in `Tuist/{ProjectName}` or tuist itself
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

    private static func strings(templateType: TemplateType) -> Self {
        .init(
            templateType: templateType,
            parser: .strings,
            extensions: ["strings", "stringsdict"]
        )
    }

    /// Default assets synthesizer defined in `Tuist/{ProjectName}` or tuist itself
    public static func assets() -> Self {
        .assets(templateType: .defaultTemplate(resourceName: "Assets"))
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

    private static func assets(templateType: TemplateType) -> Self {
        .init(
            templateType: templateType,
            parser: .assets,
            extensions: ["xcassets"]
        )
    }

    /// Default fonts synthesizer defined in `Tuist/{ProjectName}` or tuist itself
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

    private static func fonts(templateType: TemplateType) -> Self {
        .init(
            templateType: templateType,
            parser: .fonts,
            extensions: ["otf", "ttc", "ttf"]
        )
    }

    /// Default plists synthesizer defined in `Tuist/{ProjectName}` or tuist itself
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

    /// Default CoreData synthesizer defined in `Tuist/{ProjectName}`
    public static func coreData() -> Self {
        .coreData(templateType: .defaultTemplate(resourceName: "CoreData"))
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

    /// InterfaceBuilder synthesizer with a template defined in `Tuist/{ProjectName}`
    public static func interfaceBuilder() -> Self {
        .interfaceBuilder(templateType: .defaultTemplate(resourceName: "InterfaceBuilder"))
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

    /// JSON synthesizer with a template defined in `Tuist/{ProjectName}`
    public static func json() -> Self {
        .json(templateType: .defaultTemplate(resourceName: "JSON"))
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

    /// CoreData synthesizer with a template defined in `Tuist/{ProjectName}`
    public static func yaml() -> Self {
        .yaml(templateType: .defaultTemplate(resourceName: "YAML"))
    }

    private static func yaml(templateType: TemplateType) -> Self {
        .init(
            templateType: templateType,
            parser: .yaml,
            extensions: ["yml"]
        )
    }

    /// Files synthesizer defined in a plugin
    public static func files(plugin: String, extensions: Set<String>) -> Self {
        .files(
            templateType: .plugin(
                name: plugin,
                resourceName: "Files"
            ),
            extensions: extensions
        )
    }

    /// Files synthesizer with a template defined in `Tuist/{ProjectName}`
    public static func files(extensions: Set<String>) -> Self {
        .files(templateType: .defaultTemplate(resourceName: "Files"), extensions: extensions)
    }

    private static func files(templateType: TemplateType, extensions: Set<String>) -> Self {
        .init(
            templateType: templateType,
            parser: .files,
            extensions: extensions
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

    /// Custom local synthesizer defined `Tuist/ResourceSynthesizers/{name}.stencil`
    /// - Parameters:
    ///     - name: Name of synthesizer
    ///     - parser: `Parser` to use for parsing the file to obtain its data
    ///     - extensions: Set of extensions that should be parsed
    public static func custom(
        name: String,
        parser: Parser,
        extensions: Set<String>
    ) -> Self {
        .init(
            templateType: .defaultTemplate(resourceName: name),
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
