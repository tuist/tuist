import Foundation

// MARK: - Project

public class Project: Codable {
    public let name: String
    public let up: [UpCommand]
    public let targets: [Target]
    public let settings: Settings?

    public enum CodingKeys: String, CodingKey {
        case name
        case up
        case targets
        case settings
    }

    public init(name: String,
                up: [UpCommand] = [],
                settings: Settings? = nil,
                targets: [Target] = []) {
        self.name = name
        self.up = up
        self.targets = targets
        self.settings = settings
        dumpIfNeeded(self)
    }
}
