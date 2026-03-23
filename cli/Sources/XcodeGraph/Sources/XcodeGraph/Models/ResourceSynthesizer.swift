@preconcurrency import AnyCodable
import Foundation
import Path

public struct ResourceSynthesizer: Equatable, Hashable, Codable, Sendable {
    public let parser: Parser
    public let parserOptions: [String: Parser.Option]
    public let extensions: Set<String>
    public let template: Template

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

    public init(
        parser: Parser,
        parserOptions: [String: Parser.Option],
        extensions: Set<String>,
        template: Template
    ) {
        self.parser = parser
        self.parserOptions = parserOptions
        self.extensions = extensions
        self.template = template
    }

    #if DEBUG
        public static func test(
            parser: Parser = .assets,
            parserOptions: [String: Parser.Option] = [:],
            extensions: Set<String> = ["xcassets"],
            template: Template = .defaultTemplate("Assets")
        ) -> Self {
            ResourceSynthesizer(parser: parser, parserOptions: parserOptions, extensions: extensions, template: template)
        }
    #endif
}
