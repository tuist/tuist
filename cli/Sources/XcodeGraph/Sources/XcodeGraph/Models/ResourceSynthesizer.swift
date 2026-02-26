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

        public struct Option: Equatable, Hashable, Codable, Sendable {
            public var value: Any {
                anyCodableValue.value
            }

            private let anyCodableValue: AnyCodable

            public init(value: some Any) {
                anyCodableValue = AnyCodable(value)
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
}

// MARK: - ResourceSynthesizer.Parser.Option - ExpressibleByStringInterpolation

extension ResourceSynthesizer.Parser.Option: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self = .init(value: value)
    }
}

// MARK: - ResourceSynthesizer.Parser.Option - ExpressibleByIntegerLiteral

extension ResourceSynthesizer.Parser.Option: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .init(value: value)
    }
}

// MARK: - ResourceSynthesizer.Parser.Option - ExpressibleByFloatLiteral

extension ResourceSynthesizer.Parser.Option: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .init(value: value)
    }
}

// MARK: - ResourceSynthesizer.Parser.Option - ExpressibleByBooleanLiteral

extension ResourceSynthesizer.Parser.Option: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .init(value: value)
    }
}

// MARK: - ResourceSynthesizer.Parser.Option - ExpressibleByDictionaryLiteral

extension ResourceSynthesizer.Parser.Option: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, Self)...) {
        self = .init(value: Dictionary(uniqueKeysWithValues: elements))
    }
}

// MARK: - ResourceSynthesizer.Parser.Option - ExpressibleByArrayLiteral

extension ResourceSynthesizer.Parser.Option: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Self...) {
        self = .init(value: elements)
    }
}

#if DEBUG
    extension XcodeGraph.ResourceSynthesizer {
        public static func test(
            parser: Parser = .assets,
            parserOptions: [String: Parser.Option] = [:],
            extensions: Set<String> = ["xcassets"],
            template: Template = .defaultTemplate("Assets")
        ) -> Self {
            ResourceSynthesizer(parser: parser, parserOptions: parserOptions, extensions: extensions, template: template)
        }
    }
#endif
