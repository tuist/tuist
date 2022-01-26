import Foundation
import TSCBasic

public struct ResourceSynthesizer: Equatable, Hashable, Codable {
    public let parser: Parser
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
    }

    public init(
        parser: Parser,
        extensions: Set<String>,
        template: Template
    ) {
        self.parser = parser
        self.extensions = extensions
        self.template = template
    }
}
