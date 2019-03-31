import Foundation

// MARK: - Project

public class Project: Codable {
    public let name: String
    public let targets: [Target]
    public let settings: Settings?
    public let additionalFiles: [WorkspaceElement]

    public init(name: String,
                settings: Settings? = nil,
                targets: [Target] = [],
                additionalFiles: [WorkspaceElement] = []) {
        self.name = name
        self.targets = targets
        self.settings = settings
        self.additionalFiles = additionalFiles
        dumpIfNeeded(self)
    }
}
