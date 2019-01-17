import Foundation

// MARK: - Project

public class Project: Codable {
    public let name: String
    public let up: [Up]
    public let targets: [Target]
    public let schemes: [Scheme]
    public let settings: Settings?

    public enum CodingKeys: String, CodingKey {
        case name
        case up
        case targets
        case schemes
        case settings
    }

    public init(name: String,
                up: [Up] = [],
                settings: Settings? = nil,
                targets: [Target] = [],
                schemes: [Scheme] = []) {
        self.name = name
        self.up = up
        self.targets = targets
        self.schemes = schemes
        self.settings = settings
        dumpIfNeeded(self)
    }
}
