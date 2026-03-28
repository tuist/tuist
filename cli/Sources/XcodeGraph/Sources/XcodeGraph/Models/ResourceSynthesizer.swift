@preconcurrency import AnyCodable
import Foundation
import Path

public struct ResourceSynthesizer: Equatable, Hashable, Codable, Sendable {
    public let parser: Parser
    public let parserOptions: [String: Parser.Option]
    public let extensions: Set<String>
    public let template: Template
    /// Custom parameters passed directly to the Stencil template via `{{param.myKey}}`.
    /// These values override Tuist's built-in defaults (e.g. `publicAccess`, `name`, `bundle`).
    public let context: [String: Parser.Option]

    public enum Template: Equatable, Hashable, Codable, Sendable {
        case file(AbsolutePath)
        case defaultTemplate(String)
    }

    public enum Parser: String, CaseIterable, Equatable, Hashable, Codable, Sendable {
        case strings
        case stringsCatalog
        case assets
        case plists
        case fonts
        case coreData
        case interfaceBuilder
        case json
        case yaml
        case files

        public struct Option: Equatable, Hashable, Codable, Sendable, ExpressibleByStringInterpolation,
            ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral,
            ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral
        {
            public var value: Any {
                anyCodableValue.value
            }

            private let anyCodableValue: AnyCodable

            public init(value: some Any) {
                anyCodableValue = AnyCodable(value)
            }

            public init(stringLiteral value: String) {
                self = .init(value: value)
            }

            public init(integerLiteral value: Int) {
                self = .init(value: value)
            }

            public init(floatLiteral value: Double) {
                self = .init(value: value)
            }

            public init(booleanLiteral value: Bool) {
                self = .init(value: value)
            }

            public init(dictionaryLiteral elements: (String, Self)...) {
                self = .init(value: Dictionary(uniqueKeysWithValues: elements))
            }

            public init(arrayLiteral elements: Self...) {
                self = .init(value: elements)
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case parser, parserOptions, extensions, template, context
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        parser = try container.decode(Parser.self, forKey: .parser)
        parserOptions = try container.decode([String: Parser.Option].self, forKey: .parserOptions)
        extensions = try container.decode(Set<String>.self, forKey: .extensions)
        template = try container.decode(Template.self, forKey: .template)
        context = try container.decodeIfPresent([String: Parser.Option].self, forKey: .context) ?? [:]
    }

    public init(
        parser: Parser,
        parserOptions: [String: Parser.Option],
        extensions: Set<String>,
        template: Template,
        context: [String: Parser.Option] = [:]
    ) {
        self.parser = parser
        self.parserOptions = parserOptions
        self.extensions = extensions
        self.template = template
        self.context = context
    }

    #if DEBUG
        public static func test(
            parser: Parser = .assets,
            parserOptions: [String: Parser.Option] = [:],
            extensions: Set<String> = ["xcassets"],
            template: Template = .defaultTemplate("Assets"),
            context: [String: Parser.Option] = [:]
        ) -> Self {
            ResourceSynthesizer(
                parser: parser,
                parserOptions: parserOptions,
                extensions: extensions,
                template: template,
                context: context
            )
        }
    #endif
}
