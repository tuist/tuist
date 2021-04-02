import Foundation
import TSCBasic

public struct ResourceSynthesizer: Equatable, Hashable {
    public let parser: Parser
    public let extensions: Set<String>
    public let template: Template
    
    public enum Template: Equatable, Hashable {
        case file(AbsolutePath)
        case defaultTemplate(String)
    }
    
    public enum Parser: Equatable, Hashable {
        case strings
        case assets
        case plists
        case fonts
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
