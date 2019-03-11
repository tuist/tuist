import Foundation

// MARK: - Workspace

public class Workspace: Codable {

    public let name: String
    public let projects: [String]
    public let additionalFiles: [String]
    
    public init(name: String, projects: [String], additionalFiles: [String]) {
        self.name = name
        self.projects = projects
        self.additionalFiles = additionalFiles
        dumpIfNeeded(self)
    }
    
}
