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

        public enum Option: Equatable, Codable, Sendable {
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
        }
    }

    /// Default strings synthesizer defined in `Tuist/{ProjectName}` or tuist itself
    public static func strings(parserOptions: [String: Parser.Option] = [:]) -> Self {
        .strings(
            templateType: .defaultTemplate(resourceName: "Strings"),
            parserOptions: parserOptions
        )
    }

    /// Strings synthesizer defined in a plugin
    public static func strings(
        plugin: String,
        parserOptions: [String: Parser.Option] = [:]
    ) -> Self {
        .strings(
            templateType: .plugin(
                name: plugin,
                resourceName: "Strings"
            ),
            parserOptions: parserOptions
        )
    }

    private static func strings(
        templateType: TemplateType,
        parserOptions: [String: Parser.Option] = [:]
    ) -> Self {
        .init(
            templateType: templateType,
            parser: .strings,
            parserOptions: parserOptions,
            extensions: ["strings", "stringsdict"]
        )
    }

    /// Default assets synthesizer defined in `Tuist/{ProjectName}` or tuist itself
    public static func assets(parserOptions: [String: Parser.Option] = [:]) -> Self {
        .assets(
            templateType: .defaultTemplate(resourceName: "Assets"),
            parserOptions: parserOptions
        )
    }

    /// Assets synthesizer defined in a plugin
    public static func assets(
        plugin: String,
        parserOptions: [String: Parser.Option] = [:]
    ) -> Self {
        .assets(
            templateType: .plugin(
                name: plugin,
                resourceName: "Assets"
            ),
            parserOptions: parserOptions
        )
    }

    private static func assets(
        templateType: TemplateType,
        parserOptions: [String: Parser.Option] = [:]
    ) -> Self {
        .init(
            templateType: templateType,
            parser: .assets,
            parserOptions: parserOptions,
            extensions: ["xcassets"]
        )
    }

    /// Default fonts synthesizer defined in `Tuist/{ProjectName}` or tuist itself
    public static func fonts(parserOptions: [String: Parser.Option] = [:]) -> Self {
        .fonts(templateType: .defaultTemplate(resourceName: "Fonts"), parserOptions: parserOptions)
    }

    /// Fonts synthesizer defined in a plugin
    public static func fonts(
        plugin: String,
        parserOptions: [String: Parser.Option] = [:]
    ) -> Self {
        .fonts(
            templateType: .plugin(
                name: plugin,
                resourceName: "Fonts"
            ),
            parserOptions: parserOptions
        )
    }

    private static func fonts(
        templateType: TemplateType,
        parserOptions: [String: Parser.Option] = [:]
    ) -> Self {
        .init(
            templateType: templateType,
            parser: .fonts,
            parserOptions: parserOptions,
            extensions: ["otf", "ttc", "ttf", "woff"]
        )
    }

    /// Default plists synthesizer defined in `Tuist/{ProjectName}` or tuist itself
    public static func plists(parserOptions: [String: Parser.Option] = [:]) -> Self {
        .plists(
            templateType: .defaultTemplate(resourceName: "Plists"),
            parserOptions: parserOptions
        )
    }

    /// Plists synthesizer defined in a plugin
    public static func plists(
        plugin: String,
        parserOptions: [String: Parser.Option] = [:]
    ) -> Self {
        .plists(
            templateType: .plugin(
                name: plugin,
                resourceName: "Plists"
            ),
            parserOptions: parserOptions
        )
    }

    private static func plists(
        templateType: TemplateType,
        parserOptions: [String: Parser.Option] = [:]
    ) -> Self {
        .init(
            templateType: templateType,
            parser: .plists,
            parserOptions: parserOptions,
            extensions: ["plist"]
        )
    }

    /// CoreData synthesizer defined in a plugin
    public static func coreData(
        plugin: String,
        parserOptions: [String: Parser.Option] = [:]
    ) -> Self {
        .coreData(
            templateType: .plugin(
                name: plugin,
                resourceName: "CoreData"
            ),
            parserOptions: parserOptions
        )
    }

    /// Default CoreData synthesizer defined in `Tuist/{ProjectName}`
    public static func coreData(parserOptions: [String: Parser.Option] = [:]) -> Self {
        .coreData(
            templateType: .defaultTemplate(resourceName: "CoreData"),
            parserOptions: parserOptions
        )
    }

    private static func coreData(
        templateType: TemplateType,
        parserOptions: [String: Parser.Option] = [:]
    ) -> Self {
        .init(
            templateType: templateType,
            parser: .coreData,
            parserOptions: parserOptions,
            extensions: ["xcdatamodeld"]
        )
    }

    /// InterfaceBuilder synthesizer defined in a plugin
    public static func interfaceBuilder(
        plugin: String,
        parserOptions: [String: Parser.Option] = [:]
    ) -> Self {
        .interfaceBuilder(
            templateType: .plugin(
                name: plugin,
                resourceName: "InterfaceBuilder"
            ),
            parserOptions: parserOptions
        )
    }

    /// InterfaceBuilder synthesizer with a template defined in `Tuist/{ProjectName}`
    public static func interfaceBuilder(parserOptions: [String: Parser.Option] = [:]) -> Self {
        .interfaceBuilder(
            templateType: .defaultTemplate(resourceName: "InterfaceBuilder"),
            parserOptions: parserOptions
        )
    }

    private static func interfaceBuilder(
        templateType: TemplateType,
        parserOptions: [String: Parser.Option] = [:]
    ) -> Self {
        .init(
            templateType: templateType,
            parser: .interfaceBuilder,
            parserOptions: parserOptions,
            extensions: ["storyboard"]
        )
    }

    /// JSON synthesizer defined in a plugin
    public static func json(plugin: String, parserOptions: [String: Parser.Option] = [:]) -> Self {
        .coreData(
            templateType: .plugin(
                name: plugin,
                resourceName: "JSON"
            ),
            parserOptions: parserOptions
        )
    }

    /// JSON synthesizer with a template defined in `Tuist/{ProjectName}`
    public static func json(parserOptions: [String: Parser.Option] = [:]) -> Self {
        .json(
            templateType: .defaultTemplate(resourceName: "JSON"),
            parserOptions: parserOptions
        )
    }

    private static func json(
        templateType: TemplateType,
        parserOptions: [String: Parser.Option] = [:]
    ) -> Self {
        .init(
            templateType: templateType,
            parser: .json,
            parserOptions: parserOptions,
            extensions: ["json"]
        )
    }

    /// YAML synthesizer defined in a plugin
    public static func yaml(plugin: String, parserOptions: [String: Parser.Option] = [:]) -> Self {
        .yaml(
            templateType: .plugin(
                name: plugin,
                resourceName: "YAML"
            ),
            parserOptions: parserOptions
        )
    }

    /// CoreData synthesizer with a template defined in `Tuist/{ProjectName}`
    public static func yaml(parserOptions: [String: Parser.Option] = [:]) -> Self {
        .yaml(templateType: .defaultTemplate(resourceName: "YAML"), parserOptions: parserOptions)
    }

    private static func yaml(
        templateType: TemplateType,
        parserOptions: [String: Parser.Option] = [:]
    ) -> Self {
        .init(
            templateType: templateType,
            parser: .yaml,
            parserOptions: parserOptions,
            extensions: ["yml"]
        )
    }

    /// Files synthesizer defined in a plugin
    public static func files(
        plugin: String,
        parserOptions: [String: Parser.Option] = [:],
        extensions: Set<String>
    ) -> Self {
        .files(
            templateType: .plugin(
                name: plugin,
                resourceName: "Files"
            ),
            parserOptions: parserOptions,
            extensions: extensions
        )
    }

    /// Files synthesizer with a template defined in `Tuist/{ProjectName}`
    public static func files(
        parserOptions: [String: Parser.Option] = [:],
        extensions: Set<String>
    ) -> Self {
        .files(
            templateType: .defaultTemplate(resourceName: "Files"),
            parserOptions: parserOptions,
            extensions: extensions
        )
    }

    private static func files(
        templateType: TemplateType,
        parserOptions: [String: Parser.Option] = [:],
        extensions: Set<String>
    ) -> Self {
        .init(
            templateType: templateType,
            parser: .files,
            parserOptions: parserOptions,
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
        parserOptions: [String: Parser.Option] = [:],
        extensions: Set<String>,
        resourceName: String
    ) -> Self {
        .init(
            templateType: .plugin(name: plugin, resourceName: resourceName),
            parser: parser,
            parserOptions: parserOptions,
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
        parserOptions: [String: Parser.Option] = [:],
        extensions: Set<String>
    ) -> Self {
        .init(
            templateType: .defaultTemplate(resourceName: name),
            parser: parser,
            parserOptions: parserOptions,
            extensions: extensions
        )
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

// MARK: - ResourceSynthesizer.Parser.Option - ExpressibleByStringInterpolation

extension ResourceSynthesizer.Parser.Option: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

// MARK: - ResourceSynthesizer.Parser.Option - ExpressibleByIntegerLiteral

extension ResourceSynthesizer.Parser.Option: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .integer(value)
    }
}

// MARK: - ResourceSynthesizer.Parser.Option - ExpressibleByFloatLiteral

extension ResourceSynthesizer.Parser.Option: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

// MARK: - ResourceSynthesizer.Parser.Option - ExpressibleByBooleanLiteral

extension ResourceSynthesizer.Parser.Option: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .boolean(value)
    }
}

// MARK: - ResourceSynthesizer.Parser.Option - ExpressibleByDictionaryLiteral

extension ResourceSynthesizer.Parser.Option: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, Self)...) {
        self = .dictionary(Dictionary(uniqueKeysWithValues: elements))
    }
}

// MARK: - ResourceSynthesizer.Parser.Option - ExpressibleByArrayLiteral

extension ResourceSynthesizer.Parser.Option: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Self...) {
        self = .array(elements)
    }
}
