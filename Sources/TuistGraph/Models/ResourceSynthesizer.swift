import Foundation

public struct ResourceSynthesizer: Equatable, Hashable {
    public let pluginName: String?
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
        pluginName: String?,
        parser: Parser,
        extensions: Set<String>,
        templateName: String
    ) {
        self.pluginName = pluginName
        self.parser = parser
        self.extensions = extensions
        self.templateName = templateName
    }
}
