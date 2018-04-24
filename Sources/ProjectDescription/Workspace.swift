import Foundation

// MARK: - Workspace

public class Workspace {
    public let name: String
    public let projects: [String]
    public init(name: String,
                projects: [String]) {
        self.name = name
        self.projects = projects
        dumpIfNeeded(self)
    }
}

// MARK: - Workspace (JSONConvertible)

extension Workspace: JSONConvertible {
    func toJSON() -> JSON {
        return .dictionary(["name": name.toJSON(), "project": projects.toJSON()])
    }
}
