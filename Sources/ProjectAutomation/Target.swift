import Foundation

public struct Target: Codable {
    public let name: String
    public let sources: [String]
    
    public init(
        name: String,
        sources: [String]
    ) {
        self.name = name
        self.sources = sources
    }
}

public struct Graph: Codable {
    public let targets: [Target]
    
    public init(
        targets: [Target]
    ) {
        self.targets = targets
    }
}
