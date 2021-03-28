import Foundation

public struct ResourceSynthesizer: Equatable, Hashable {
    public let pluginName: String?
    public let resourceType: ResourceType
    
    public enum ResourceType: Equatable, Hashable {
        case strings
        case assets
        case plists
        case fonts
        
        public var name: String {
            switch self {
            case .strings:
                return "Strings"
            case .assets:
                return "Assets"
            case .plists:
                return "Plists"
            case .fonts:
                return "Fonts"
            }
        }
    }
    
    public init(
        pluginName: String?,
        resourceType: ResourceType
    ) {
        self.pluginName = pluginName
        self.resourceType = resourceType
    }
}
