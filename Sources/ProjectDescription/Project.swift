import Foundation

// MARK: - Project

public class Project: Codable {
    public let name: String
    public let targets: [Target]
    public let schemes: [Scheme]
    public let settings: Settings?
    public let additionalFiles: [FileElement]

    public init(name: String,
                settings: Settings? = nil,
                targets: [Target] = [],
                schemes: [Scheme] = [],
                additionalFiles: [FileElement] = []) {
        self.name = name
        self.targets = targets
        self.schemes = schemes
        self.settings = settings
        self.additionalFiles = additionalFiles
        dumpIfNeeded(self)
    }
}
