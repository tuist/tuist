import Path

/// It represents a workflow in a project's directory.
public struct Workflow: Codable, Equatable, Sendable, Hashable, Comparable {
    /// The path to the Package.swift file that declares the workflow.
    public let packageSwiftPath: AbsolutePath
    
    /// The name of the workflow
    public let name: String
    
    /// The description of the workflow.
    public let description: String?
    
    public static func < (lhs: Workflow, rhs: Workflow) -> Bool {
        lhs.packageSwiftPath < rhs.packageSwiftPath
    }
}
