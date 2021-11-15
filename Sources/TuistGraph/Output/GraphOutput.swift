import Foundation
import TSCBasic

/// The structure defining the output schema of the entire project graph.
public struct GraphOutput: Codable, Equatable {
    /// The name of this graph.
    public let name: String

    /// The absolute path of this graph.
    public let path: String

    /// The projects within this graph.
    public let projects: [String: ProjectOutput]

    public init(name: String, path: String, projects: [String: ProjectOutput]) {
        self.name = name
        self.path = path
        self.projects = projects
    }
}
