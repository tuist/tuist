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
    
    /// Factory function that converts the internal Graph model to the output model.
    public static func from(_ graph: Graph) -> GraphOutput {
        let projects = graph.projects.reduce(into: [String: ProjectOutput](), {$0[$1.key.pathString] = ProjectOutput.from($1.value)})
        
        return GraphOutput(name: graph.name, path: graph.path.pathString, projects: projects)
    }
}
