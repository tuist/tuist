/// A resource synthesizer for given file extensions.
///
/// For example to synthesize resource accessors for strings, you can use:
/// - `.strings()` for tuist's default
/// - `.strings(parserOptions: ["separator": "/"])` to use strings template with SwiftGen Parser Options
/// - `.strings(plugin: "MyPlugin")` to use strings template from a plugin
/// - `.strings(templatePath: "Templates/Strings.stencil")` to use strings template at a given path
public struct ResourceSynthesizer: Codable, Equatable, Sendable { // swiftlint:disable:this type_body_length
    /// Templates can be of multiple types
    public var template: Template
    public var parser: Parser
    public var parserOptions: [String: Parser.Option]
    public var extensions: Set<String>
    public var templateParameters: [String: Template.Parameter]

    /// Templates can be either a local template file, from a plugin, or a default template from tuist
    public enum Template: Codable, Equatable, Sendable {
        /// Plugin template file
        /// `name` is a name of a plugin
        /// `resourceName` is a name of the resource - that is used for finding a template as well as naming the resulting
        /// `.swift` file
        case plugin(name: String, resourceName: String)
        /// Default template defined `Tuist/{ProjectName}`, or if not present there, in tuist itself
        /// `resourceName` is used for the name of the resulting `.swift` file
        case defaultTemplate(resourceName: String)

        public enum Parameter: Equatable, Codable, Sendable {
            /// It represents a string value.
            case string(String)
            /// It represents an integer value.
            case integer(Int)
            /// It represents a floating value.
            case double(Double)
            /// It represents a boolean value.
            case boolean(Bool)
            /// It represents a dictionary value.
            case dictionary([String: Parameter])
            /// It represents an array value.
            case array([Parameter])
        }
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

    // MARK: - Strings

    /// Default strings synthesizer defined in `Tuist/{ProjectName}` or tuist itself
    public static func strings(
        parserOptions: [String: Parser.Option] = [:],
        templateParameters: [String: Template.Parameter] = [:]
    ) -> Self {
        .strings(
            template: .defaultTemplate(resourceName: "Strings"),
            parserOptions: parserOptions,
            templateParameters: templateParameters
        )
    }

    /// Strings synthesizer defined in a plugin
    public static func strings(
        plugin: String,
        parserOptions: [String: Parser.Option] = [:],
        templateParameters: [String: Template.Parameter] = [:]
    ) -> Self {
        .strings(
            template: .plugin(
                name: plugin,
                resourceName: "Strings"
            ),
            parserOptions: parserOptions,
            templateParameters: templateParameters
        )
    }

    private static func strings(
        template: Template,
        parserOptions: [String: Parser.Option],
        templateParameters: [String: Template.Parameter]
    ) -> Self {
        .init(
            template: template,
            parser: .strings,
            parserOptions: parserOptions,
            extensions: ["strings", "stringsdict"],
            templateParameters: templateParameters
        )
    }

    // MARK: - Assets

    /// Default assets synthesizer defined in `Tuist/{ProjectName}` or tuist itself
    public static func assets(
        parserOptions: [String: Parser.Option] = [:],
        templateParameters: [String: Template.Parameter] = [:]
    ) -> Self {
        .assets(
            template: .defaultTemplate(resourceName: "Assets"),
            parserOptions: parserOptions,
            templateParameters: templateParameters
        )
    }

    /// Assets synthesizer defined in a plugin
    public static func assets(
        plugin: String,
        parserOptions: [String: Parser.Option] = [:],
        templateParameters: [String: Template.Parameter] = [:]
    ) -> Self {
        .assets(
            template: .plugin(
                name: plugin,
                resourceName: "Assets"
            ),
            parserOptions: parserOptions,
            templateParameters: templateParameters
        )
    }

    private static func assets(
        template: Template,
        parserOptions: [String: Parser.Option],
        templateParameters: [String: Template.Parameter]
    ) -> Self {
        .init(
            template: template,
            parser: .assets,
            parserOptions: parserOptions,
            extensions: ["xcassets"],
            templateParameters: templateParameters
        )
    }

    // MARK: - Fonts

    /// Default fonts synthesizer defined in `Tuist/{ProjectName}` or tuist itself
    public static func fonts(
        parserOptions: [String: Parser.Option] = [:],
        templateParameters: [String: Template.Parameter] = [:]
    ) -> Self {
        .fonts(
            template: .defaultTemplate(resourceName: "Fonts"),
            parserOptions: parserOptions,
            templateParameters: templateParameters
        )
    }

    /// Fonts synthesizer defined in a plugin
    public static func fonts(
        plugin: String,
        parserOptions: [String: Parser.Option] = [:],
        templateParameters: [String: Template.Parameter] = [:]
    ) -> Self {
        .fonts(
            template: .plugin(
                name: plugin,
                resourceName: "Fonts"
            ),
            parserOptions: parserOptions,
            templateParameters: templateParameters
        )
    }

    private static func fonts(
        template: Template,
        parserOptions: [String: Parser.Option],
        templateParameters: [String: Template.Parameter]
    ) -> Self {
        .init(
            template: template,
            parser: .fonts,
            parserOptions: parserOptions,
            extensions: ["otf", "ttc", "ttf", "woff"],
            templateParameters: templateParameters
        )
    }

    // MARK: - Plist

    /// Default plists synthesizer defined in `Tuist/{ProjectName}` or tuist itself
    public static func plists(
        parserOptions: [String: Parser.Option] = [:],
        templateParameters: [String: Template.Parameter] = [:]
    ) -> Self {
        .plists(
            template: .defaultTemplate(resourceName: "Plists"),
            parserOptions: parserOptions,
            templateParameters: templateParameters
        )
    }

    /// Plists synthesizer defined in a plugin
    public static func plists(
        plugin: String,
        parserOptions: [String: Parser.Option] = [:],
        templateParameters: [String: Template.Parameter] = [:]
    ) -> Self {
        .plists(
            template: .plugin(
                name: plugin,
                resourceName: "Plists"
            ),
            parserOptions: parserOptions,
            templateParameters: templateParameters
        )
    }

    private static func plists(
        template: Template,
        parserOptions: [String: Parser.Option],
        templateParameters: [String: Template.Parameter]
    ) -> Self {
        .init(
            template: template,
            parser: .plists,
            parserOptions: parserOptions,
            extensions: ["plist"],
            templateParameters: templateParameters
        )
    }

    // MARK: - Core Data

    /// CoreData synthesizer defined in a plugin
    public static func coreData(
        plugin: String,
        parserOptions: [String: Parser.Option] = [:],
        templateParameters: [String: Template.Parameter] = [:]
    ) -> Self {
        .coreData(
            template: .plugin(
                name: plugin,
                resourceName: "CoreData"
            ),
            parserOptions: parserOptions,
            templateParameters: templateParameters
        )
    }

    /// Default CoreData synthesizer defined in `Tuist/{ProjectName}`
    public static func coreData(
        parserOptions: [String: Parser.Option] = [:],
        templateParameters: [String: Template.Parameter] = [:]
    ) -> Self {
        .coreData(
            template: .defaultTemplate(resourceName: "CoreData"),
            parserOptions: parserOptions,
            templateParameters: templateParameters
        )
    }

    private static func coreData(
        template: Template,
        parserOptions: [String: Parser.Option],
        templateParameters: [String: Template.Parameter]
    ) -> Self {
        .init(
            template: template,
            parser: .coreData,
            parserOptions: parserOptions,
            extensions: ["xcdatamodeld"],
            templateParameters: templateParameters
        )
    }

    // MARK: - Interface Builder

    /// InterfaceBuilder synthesizer defined in a plugin
    public static func interfaceBuilder(
        plugin: String,
        parserOptions: [String: Parser.Option] = [:],
        templateParameters: [String: Template.Parameter] = [:]
    ) -> Self {
        .interfaceBuilder(
            template: .plugin(
                name: plugin,
                resourceName: "InterfaceBuilder"
            ),
            parserOptions: parserOptions,
            templateParameters: templateParameters
        )
    }

    /// InterfaceBuilder synthesizer with a template defined in `Tuist/{ProjectName}`
    public static func interfaceBuilder(
        parserOptions: [String: Parser.Option] = [:],
        templateParameters: [String: Template.Parameter] = [:]
    ) -> Self {
        .interfaceBuilder(
            template: .defaultTemplate(resourceName: "InterfaceBuilder"),
            parserOptions: parserOptions,
            templateParameters: templateParameters
        )
    }

    private static func interfaceBuilder(
        template: Template,
        parserOptions: [String: Parser.Option],
        templateParameters: [String: Template.Parameter]
    ) -> Self {
        .init(
            template: template,
            parser: .interfaceBuilder,
            parserOptions: parserOptions,
            extensions: ["storyboard"],
            templateParameters: templateParameters
        )
    }

    // MARK: - JSON

    /// JSON synthesizer defined in a plugin
    public static func json(
        plugin: String,
        parserOptions: [String: Parser.Option] = [:],
        templateParameters: [String: Template.Parameter] = [:]
    ) -> Self {
        .json(
            template: .plugin(
                name: plugin,
                resourceName: "JSON"
            ),
            parserOptions: parserOptions,
            templateParameters: templateParameters
        )
    }

    /// JSON synthesizer with a template defined in `Tuist/{ProjectName}`
    public static func json(
        parserOptions: [String: Parser.Option] = [:],
        templateParameters: [String: Template.Parameter] = [:]
    ) -> Self {
        .json(
            template: .defaultTemplate(resourceName: "JSON"),
            parserOptions: parserOptions,
            templateParameters: templateParameters
        )
    }

    private static func json(
        template: Template,
        parserOptions: [String: Parser.Option],
        templateParameters: [String: Template.Parameter]
    ) -> Self {
        .init(
            template: template,
            parser: .json,
            parserOptions: parserOptions,
            extensions: ["json"],
            templateParameters: templateParameters
        )
    }

    // MARK: - YAML

    /// YAML synthesizer defined in a plugin
    public static func yaml(
        plugin: String,
        parserOptions: [String: Parser.Option] = [:],
        templateParameters: [String: Template.Parameter] = [:]
    ) -> Self {
        .yaml(
            template: .plugin(
                name: plugin,
                resourceName: "YAML"
            ),
            parserOptions: parserOptions,
            templateParameters: templateParameters
        )
    }

    /// YAML synthesizer with a template defined in `Tuist/{ProjectName}`
    public static func yaml(
        parserOptions: [String: Parser.Option] = [:],
        templateParameters: [String: Template.Parameter] = [:]
    ) -> Self {
        .yaml(
            template: .defaultTemplate(resourceName: "YAML"),
            parserOptions: parserOptions,
            templateParameters: templateParameters
        )
    }

    private static func yaml(
        template: Template,
        parserOptions: [String: Parser.Option],
        templateParameters: [String: Template.Parameter]
    ) -> Self {
        .init(
            template: template,
            parser: .yaml,
            parserOptions: parserOptions,
            extensions: ["yml", "yaml"],
            templateParameters: templateParameters
        )
    }

    // MARK: - Files

    /// Files synthesizer defined in a plugin
    public static func files(
        plugin: String,
        parserOptions: [String: Parser.Option] = [:],
        extensions: Set<String>,
        templateParameters: [String: Template.Parameter] = [:]
    ) -> Self {
        .files(
            template: .plugin(
                name: plugin,
                resourceName: "Files"
            ),
            parserOptions: parserOptions,
            extensions: extensions,
            templateParameters: templateParameters
        )
    }

    /// Files synthesizer with a template defined in `Tuist/{ProjectName}`
    public static func files(
        parserOptions: [String: Parser.Option] = [:],
        extensions: Set<String>,
        templateParameters: [String: Template.Parameter] = [:]
    ) -> Self {
        .files(
            template: .defaultTemplate(resourceName: "Files"),
            parserOptions: parserOptions,
            extensions: extensions,
            templateParameters: templateParameters
        )
    }

    private static func files(
        template: Template,
        parserOptions: [String: Parser.Option],
        extensions: Set<String>,
        templateParameters: [String: Template.Parameter]
    ) -> Self {
        .init(
            template: template,
            parser: .files,
            parserOptions: parserOptions,
            extensions: extensions,
            templateParameters: templateParameters
        )
    }

    // MARK: - Custom

    /// Custom synthesizer from a plugin
    /// - Parameters:
    ///     - plugin: Name of a plugin where resource synthesizer template is located
    ///     - parser: `Parser` to use for parsing the file to obtain its data
    ///     - extensions: Set of extensions that should be parsed
    ///     - resourceName: Name of the template file and the resulting `.swift` file
    ///     - templateParameters: Custom parameters that will be passed to the Stencil template
    public static func custom(
        plugin: String,
        parser: Parser,
        parserOptions: [String: Parser.Option] = [:],
        extensions: Set<String>,
        resourceName: String,
        templateParameters: [String: Template.Parameter] = [:]
    ) -> Self {
        .init(
            template: .plugin(name: plugin, resourceName: resourceName),
            parser: parser,
            parserOptions: parserOptions,
            extensions: extensions,
            templateParameters: templateParameters
        )
    }

    /// Custom local synthesizer defined `Tuist/ResourceSynthesizers/{name}.stencil`
    /// - Parameters:
    ///     - name: Name of synthesizer
    ///     - parser: `Parser` to use for parsing the file to obtain its data
    ///     - extensions: Set of extensions that should be parsed
    ///     - templateParameters: Custom parameters that will be passed to the Stencil template
    public static func custom(
        name: String,
        parser: Parser,
        parserOptions: [String: Parser.Option] = [:],
        extensions: Set<String>,
        templateParameters: [String: Template.Parameter] = [:]
    ) -> Self {
        .init(
            template: .defaultTemplate(resourceName: name),
            parser: parser,
            parserOptions: parserOptions,
            extensions: extensions,
            templateParameters: templateParameters
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

/// Provide helpers for tuist embedded templates.
extension [String: ResourceSynthesizer.Template.Parameter] {
    /// Helper function to configure template parameters available for strings.
    /// - Parameters:
    ///   - publicAccess: If set, the generated constants will be marked as `public`. Otherwise, they'll be declared `internal`.
    ///   - name: Allows you to change the name of the generated `enum` containing all string tables.
    ///   - forceFileNameEnum: Setting this parameter will generate an `enum <FileName>`
    ///                        even if only one FileName was provided as input.
    ///   - lookupFunction: Allows you to set your own custom localization function.
    ///   - noComments: Setting this parameter will disable the comments containing the comment from the strings file
    ///                 or the translation of a key.
    /// - Returns: A dictionary containing configured parameters.
    public static func strings(
        publicAccess: Bool? = nil,
        name: String? = nil,
        forceFileNameEnum: Bool? = nil,
        lookupFunction: String? = nil,
        noComments: Bool? = nil
    ) -> Self {
        var parameters: Self = [:]

        if let publicAccess {
            parameters["publicAccess"] = .boolean(publicAccess)
        }

        if let name {
            parameters["name"] = .string(name)
        }

        if let forceFileNameEnum {
            parameters["forceFileNameEnum"] = .boolean(forceFileNameEnum)
        }

        if let lookupFunction {
            parameters["lookupFunction"] = .string(lookupFunction)
        }

        if let noComments {
            parameters["noComments"] = .boolean(noComments)
        }

        return parameters
    }

    /// Helper function to configure template parameters available for assets.
    /// - Parameters:
    ///   - publicAccess: If set, the generated constants will be marked as `public`. Otherwise, they'll be declared `internal`.
    ///   - name: Allows you to change the name of the generated enum containing all assets.
    ///   - forceFileNameEnum: Setting this parameter will generate an `enum <FileName>`
    ///                        even if only one FileName was provided as input.
    ///   - allValues: Setting this parameter will enable the generation of the `allColors`, `allImages` and other such constants.
    /// - Returns: A dictionary containing configured parameters.
    public static func assets(
        publicAccess: Bool? = nil,
        name: String? = nil,
        forceFileNameEnum: Bool? = nil,
        allValues: Bool? = nil
    ) -> Self {
        var parameters: Self = [:]

        if let publicAccess {
            parameters["publicAccess"] = .boolean(publicAccess)
        }

        if let name {
            parameters["name"] = .string(name)
        }

        if let forceFileNameEnum {
            parameters["forceFileNameEnum"] = .boolean(forceFileNameEnum)
        }

        if let allValues {
            parameters["allValues"] = .boolean(allValues)
        }

        return parameters
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

// MARK: - ResourceSynthesizer.Template.Parameter - ExpressibleByStringInterpolation

extension ResourceSynthesizer.Template.Parameter: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

// MARK: - ResourceSynthesizer.Template.Parameter - ExpressibleByIntegerLiteral

extension ResourceSynthesizer.Template.Parameter: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .integer(value)
    }
}

// MARK: - ResourceSynthesizer.Template.Parameter - ExpressibleByFloatLiteral

extension ResourceSynthesizer.Template.Parameter: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

// MARK: - ResourceSynthesizer.Template.Parameter - ExpressibleByBooleanLiteral

extension ResourceSynthesizer.Template.Parameter: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .boolean(value)
    }
}

// MARK: - ResourceSynthesizer.Template.Parameter - ExpressibleByDictionaryLiteral

extension ResourceSynthesizer.Template.Parameter: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, Self)...) {
        self = .dictionary(Dictionary(uniqueKeysWithValues: elements))
    }
}

// MARK: - ResourceSynthesizer.Template.Parameter - ExpressibleByArrayLiteral

extension ResourceSynthesizer.Template.Parameter: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Self...) {
        self = .array(elements)
    }
}
