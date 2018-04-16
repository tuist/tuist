import Foundation

// MARK: - Workspace

public class Workspace {
    public let projects: [String]
    public init(projects: [String]) {
        self.projects = projects
        dumpIfNeeded(self)
    }
}

// MARK: - Workspace (JSONConvertible)

extension Workspace: JSONConvertible {
    func toJSON() -> JSON {
        return projects.toJSON()
    }
}
