import AnyCodable
import Foundation
import TSCBasic

public struct ResourceSynthesizer: Equatable, Hashable, Codable {
    public let parser: Parser
    public let parserOptions: [String: Parser.Option]
    public let extensions: Set<String>
    public let template: Template

    public enum Template: Equatable, Hashable, Codable {
        case file(AbsolutePath)
        case defaultTemplate(String)
    }

    public enum Parser: String, Equatable, Hashable, Codable {
        case strings
        case assets
        case plists
        case fonts
        case coreData
        case interfaceBuilder
        case json
        case yaml
        case files

        public struct Option: Equatable, Hashable, Codable {
            public var value: Any { anyCodableValue.value }
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
