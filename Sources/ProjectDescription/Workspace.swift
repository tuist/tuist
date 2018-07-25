import Foundation

// MARK: - Workspace

public class Workspace: Codable {
    public let name: String
    public let projects: [String]
    public init(name: String,
                projects: [String]) {
        self.name = name
        self.projects = projects
        dumpIfNeeded(self)
    }
}
