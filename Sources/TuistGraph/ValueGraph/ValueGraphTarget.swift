import Foundation
import TSCBasic

public struct ValueGraphTarget: Equatable, Hashable, Comparable, CustomDebugStringConvertible, CustomStringConvertible {
    /// Path to the directory that contains the project where the target is defined.
    public let path: AbsolutePath

    /// Target representation.
    public let target: Target

    /// Project that contains the target.
    public let project: Project
    
    public init(path: AbsolutePath, target: Target, project: Project) {
        self.path = path
        self.target = target
        self.project = project
    }

    public static func < (lhs: ValueGraphTarget, rhs: ValueGraphTarget) -> Bool {
        (lhs.path, lhs.target) < (rhs.path, rhs.target)
    }

    // MARK: - CustomDebugStringConvertible/CustomStringConvertible

    public var debugDescription: String {
        description
    }

    public var description: String {
        "Target '\(target.name)' at path '\(project.path)'"
    }
}
