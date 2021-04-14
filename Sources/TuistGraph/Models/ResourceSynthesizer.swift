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

// MARK: - ResourceSynthesizer.Template - Codable

extension ResourceSynthesizer.Template {
    private enum Kind: String, Codable {
        case file
        case defaultTemplate
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case file
        case template
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .file:
            let file = try container.decode(AbsolutePath.self, forKey: .file)
            self = .file(file)
        case .defaultTemplate:
            let template = try container.decode(String.self, forKey: .template)
            self = .defaultTemplate(template)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .file(file):
            try container.encode(Kind.file, forKey: .kind)
            try container.encode(file, forKey: .file)
        case let .defaultTemplate(template):
            try container.encode(Kind.defaultTemplate, forKey: .kind)
            try container.encode(template, forKey: .template)
        }
    }
}
