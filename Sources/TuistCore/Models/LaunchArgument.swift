import Foundation

public struct LaunchArgument: Equatable, Codable {
    // MARK: - Attributes
    
    public let name: String
    public let isEnabled: Bool
    
    // MARK: - Initi
    
    public init(name: String, isEnabled: Bool) {
        self.name = name
        self.isEnabled = isEnabled
    }
}
