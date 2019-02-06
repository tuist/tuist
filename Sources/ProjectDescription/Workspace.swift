import Foundation

// MARK: - Workspace

public class Workspace: Codable {
    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case name
        case projects
    }

    // Workspace name
    public let name: String

    // Relative paths to the projects.
    // Note: The paths are relative from the folder that contains the workspace.
    public let projects: [String]

    public init(name: String,
                projects: [String]) {
        self.name = name
        self.projects = projects
        // swiftlint:disable:next force_try
        try! dumpIfNeeded(self)
    }
}
