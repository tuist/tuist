import Path

/// It represents a workflow in a project's directory.
public struct Workflow: Equatable, Sendable, Hashable, Comparable {
    /// The path to the Swift file representing the workflow.
    let path: AbsolutePath
    
    /// The name of the workflow
    let name: String
    
    public static func < (lhs: Workflow, rhs: Workflow) -> Bool {
        lhs.path < rhs.path
    }
}
