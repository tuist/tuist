import Foundation
import TSCBasic

public struct ResourceSynthesizer: Equatable, Hashable {
    public let templatePath: AbsolutePath?
    public let parser: Parser
    public let extensions: Set<String>
    public let templateName: String
    
    public enum Parser: Equatable, Hashable {
        case strings
        case assets
        case plists
        case fonts
    }
    
    public init(
        templatePath: AbsolutePath?,
        parser: Parser,
        extensions: Set<String>,
        templateName: String
    ) {
        self.templatePath = templatePath
        self.parser = parser
        self.extensions = extensions
        self.templateName = templateName
    }
}
