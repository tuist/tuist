/// A resource synthesizer for given file extensions.
///
/// For example to synthesize resource accessors for strings, you can use:
/// - `.strings()` for tuist's default
/// - `.strings(parserOptions: ["separator": "/"])` to use strings template with SwiftGen Parser Options
/// - `.strings(plugin: "MyPlugin")` to use strings template from a plugin
/// - `.strings(templatePath: "Templates/Strings.stencil")` to use strings template at a given path
public struct ResourceSynthesizer: Codable, Equatable, Sendable { // swiftlint:disable:this type_body_length
    /// Templates can be of multiple types
    public var templateType: TemplateType
    public var parser: Parser
    public var parserOptions: [String: Parser.Option]
    public var extensions: Set<String>
    /// Custom parameters passed directly to the Stencil template via `{{param.myKey}}`.
    /// These values override Tuist's built-in defaults (e.g. `publicAccess`, `name`, `bundle`).
    public var context: [String: Parser.Option]

    private enum CodingKeys: String, CodingKey {
        case templateType, parser, parserOptions, extensions, context
    }

    public init(
        templateType: TemplateType,
        parser: Parser,
        parserOptions: [String: Parser.Option],
        extensions: Set<String>,
        context: [String: Parser.Option] = [:]
    ) {
        self.templateType = templateType
        self.parser = parser
        self.parserOptions = parserOptions
        self.extensions = extensions
        self.context = context
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        templateType = try container.decode(TemplateType.self, forKey: .templateType)
        parser = try container.decode(Parser.self, forKey: .parser)
        parserOptions = try container.decode([String: Parser.Option].self, forKey: .parserOptions)
        extensions = try container.decode(Set<String>.self, forKey: .extensions)
        context = try container.decodeIfPresent([String: Parser.Option].self, forKey: .context) ?? [:]
    }

    /// Templates can be either a local template file, from a plugin, or a default template from tuist
    public enum TemplateType: Codable, Equatable, Sendable {
        /// Plugin template file
        /// `name` is a name of a plugin
        /// `resourceName` is a name of the resource - that is used for finding a template as well as naming the resulting
        /// `.swift` file
        case plugin(name: String, resourceName: String)
        /// Default template defined `Tuist/{ProjectName}`, or if not present there, in tuist itself
        /// `resourceName` is used for the name of the resulting `.swift` file
        case defaultTemplate(resourceName: String)
    }

    /// There are multiple parsers you can choose from
    /// Each parser will give you different metadata from a file
    /// You can read more about available parsers and how to use their metadata here:
    /// https://github.com/SwiftGen/SwiftGen#available-parsers
    public enum Parser: String, Codable, Sendable {
        case strings
        case assets
        case plists
        case fonts
        case coreData
        case interfaceBuilder
        case json
        case yaml
        case files

        public enum Option: Equatable, Codable, Sendable, ExpressibleByStringInterpolation,
            ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral,
            ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral
        {
            /// It represents a string value.
            case string(String)
            /// It represents an integer value.
            case integer(Int)
            /// It represents a floating value.
            case double(Double)
            /// It represents a boolean value.
            case boolean(Bool)
            /// It represents a dictionary value.
            case dictionary([String: Option])
            /// It represents an array value.
            case array([Option])

            public init(stringLiteral value: String) {
                self = .string(value)
            }

            public init(integerLiteral value: Int) {
                self = .integer(value)
            }

            public init(floatLiteral value: Double) {
                self = .double(value)
            }

            public init(booleanLiteral value: Bool) {
                self = .boolean(value)
            }

            public init(dictionaryLiteral elements: (String, Self)...) {
                self = .dictionary(Dictionary(uniqueKeysWithValues: elements))
            }

            public init(arrayLiteral elements: Self...) {
                self = .array(elements)
            }
        }
    }

    /// Default strings synthesizer defined in `Tuist/{ProjectName}` or tuist itself
    public static func strings(parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .strings(templateType: .defaultTemplate(resourceName: "Strings"), parserOptions: parserOptions, context: context)
    }

    /// Strings synthesizer defined in a plugin
    public static func strings(plugin: String, parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .strings(templateType: .plugin(name: plugin, resourceName: "Strings"), parserOptions: parserOptions, context: context)
    }

    private static func strings(templateType: TemplateType, parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .init(templateType: templateType, parser: .strings, parserOptions: parserOptions, extensions: ["strings", "stringsdict"], context: context)
    }

    /// Default assets synthesizer defined in `Tuist/{ProjectName}` or tuist itself
    public static func assets(parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .assets(templateType: .defaultTemplate(resourceName: "Assets"), parserOptions: parserOptions, context: context)
    }

    /// Assets synthesizer defined in a plugin
    public static func assets(plugin: String, parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .assets(templateType: .plugin(name: plugin, resourceName: "Assets"), parserOptions: parserOptions, context: context)
    }

    private static func assets(templateType: TemplateType, parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .init(templateType: templateType, parser: .assets, parserOptions: parserOptions, extensions: ["xcassets"], context: context)
    }

    /// Default fonts synthesizer defined in `Tuist/{ProjectName}` or tuist itself
    public static func fonts(parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .fonts(templateType: .defaultTemplate(resourceName: "Fonts"), parserOptions: parserOptions, context: context)
    }

    /// Fonts synthesizer defined in a plugin
    public static func fonts(plugin: String, parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .fonts(templateType: .plugin(name: plugin, resourceName: "Fonts"), parserOptions: parserOptions, context: context)
    }

    private static func fonts(templateType: TemplateType, parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .init(templateType: templateType, parser: .fonts, parserOptions: parserOptions, extensions: ["otf", "ttc", "ttf", "woff"], context: context)
    }

    /// Default plists synthesizer defined in `Tuist/{ProjectName}` or tuist itself
    public static func plists(parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .plists(templateType: .defaultTemplate(resourceName: "Plists"), parserOptions: parserOptions, context: context)
    }

    /// Plists synthesizer defined in a plugin
    public static func plists(plugin: String, parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .plists(templateType: .plugin(name: plugin, resourceName: "Plists"), parserOptions: parserOptions, context: context)
    }

    private static func plists(templateType: TemplateType, parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .init(templateType: templateType, parser: .plists, parserOptions: parserOptions, extensions: ["plist"], context: context)
    }

    /// CoreData synthesizer defined in a plugin
    public static func coreData(plugin: String, parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .coreData(templateType: .plugin(name: plugin, resourceName: "CoreData"), parserOptions: parserOptions, context: context)
    }

    /// Default CoreData synthesizer defined in `Tuist/{ProjectName}`
    public static func coreData(parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .coreData(templateType: .defaultTemplate(resourceName: "CoreData"), parserOptions: parserOptions, context: context)
    }

    private static func coreData(templateType: TemplateType, parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .init(templateType: templateType, parser: .coreData, parserOptions: parserOptions, extensions: ["xcdatamodeld"], context: context)
    }

    /// InterfaceBuilder synthesizer defined in a plugin
    public static func interfaceBuilder(plugin: String, parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .interfaceBuilder(templateType: .plugin(name: plugin, resourceName: "InterfaceBuilder"), parserOptions: parserOptions, context: context)
    }

    /// InterfaceBuilder synthesizer with a template defined in `Tuist/{ProjectName}`
    public static func interfaceBuilder(parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .interfaceBuilder(templateType: .defaultTemplate(resourceName: "InterfaceBuilder"), parserOptions: parserOptions, context: context)
    }

    private static func interfaceBuilder(templateType: TemplateType, parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .init(templateType: templateType, parser: .interfaceBuilder, parserOptions: parserOptions, extensions: ["storyboard"], context: context)
    }

    /// JSON synthesizer defined in a plugin
    public static func json(plugin: String, parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .json(templateType: .plugin(name: plugin, resourceName: "JSON"), parserOptions: parserOptions, context: context)
    }

    /// JSON synthesizer with a template defined in `Tuist/{ProjectName}`
    public static func json(parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .json(templateType: .defaultTemplate(resourceName: "JSON"), parserOptions: parserOptions, context: context)
    }

    private static func json(templateType: TemplateType, parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .init(templateType: templateType, parser: .json, parserOptions: parserOptions, extensions: ["json"], context: context)
    }

    /// YAML synthesizer defined in a plugin
    public static func yaml(plugin: String, parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .yaml(templateType: .plugin(name: plugin, resourceName: "YAML"), parserOptions: parserOptions, context: context)
    }

    /// YAML synthesizer with a template defined in `Tuist/{ProjectName}`
    public static func yaml(parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .yaml(templateType: .defaultTemplate(resourceName: "YAML"), parserOptions: parserOptions, context: context)
    }

    private static func yaml(templateType: TemplateType, parserOptions: [String: Parser.Option] = [:], context: [String: Parser.Option] = [:]) -> Self {
        .init(templateType: templateType, parser: .yaml, parserOptions: parserOptions, extensions: ["yml"], context: context)
    }

    /// Files synthesizer defined in a plugin
    public static func files(plugin: String, parserOptions: [String: Parser.Option] = [:], extensions: Set<String>, context: [String: Parser.Option] = [:]) -> Self {
        .files(templateType: .plugin(name: plugin, resourceName: "Files"), parserOptions: parserOptions, extensions: extensions, context: context)
    }

    /// Files synthesizer with a template defined in `Tuist/{ProjectName}`
    public static func files(parserOptions: [String: Parser.Option] = [:], extensions: Set<String>, context: [String: Parser.Option] = [:]) -> Self {
        .files(templateType: .defaultTemplate(resourceName: "Files"), parserOptions: parserOptions, extensions: extensions, context: context)
    }

    private static func files(templateType: TemplateType, parserOptions: [String: Parser.Option] = [:], extensions: Set<String>, context: [String: Parser.Option] = [:]) -> Self {
        .init(templateType: templateType, parser: .files, parserOptions: parserOptions, extensions: extensions, context: context)
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
        parserOptions: [String: Parser.Option] = [:],
        extensions: Set<String>,
        resourceName: String,
        context: [String: Parser.Option] = [:]
    ) -> Self {
        .init(templateType: .plugin(name: plugin, resourceName: resourceName), parser: parser, parserOptions: parserOptions, extensions: extensions, context: context)
    }

    /// Custom local synthesizer defined `Tuist/ResourceSynthesizers/{name}.stencil`
    /// - Parameters:
    ///     - name: Name of synthesizer
    ///     - parser: `Parser` to use for parsing the file to obtain its data
    ///     - extensions: Set of extensions that should be parsed
    public static func custom(
        name: String,
        parser: Parser,
        parserOptions: [String: Parser.Option] = [:],
        extensions: Set<String>,
        context: [String: Parser.Option] = [:]
    ) -> Self {
        .init(templateType: .defaultTemplate(resourceName: name), parser: parser, parserOptions: parserOptions, extensions: extensions, context: context)
    }
}

extension [ResourceSynthesizer] {
    public static var `default`: Self {
        [
            .strings(),
            .assets(),
            .plists(),
            .fonts(),
        ]
    }
}
