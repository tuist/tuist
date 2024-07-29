import Foundation
import Path
import XcodeGraph

/// It represents a target that has been hashed.
public struct GraphHashedTarget: Equatable, Hashable {
    /// Path to the directory containing the project.
    let projectPath: AbsolutePath

    /// Name of the hashed target.
    let targetName: String
}
