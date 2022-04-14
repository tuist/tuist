import Foundation

/// A target reference for a specified project.
///
/// The project is specified through the path and should contain the target name.
public struct TargetReference: Equatable, Codable, ExpressibleByStringInterpolation {
    /// Path to the target's project directory.
    public var projectPath: Path?
    /// Name of the target.
    public var targetName: String

    public init(projectPath: Path?, target: String) {
        self.projectPath = projectPath
        targetName = target
    }

    public init(stringLiteral value: String) {
        self = .init(projectPath: nil, target: value)
    }

    public static func project(path: Path, target: String) -> TargetReference {
        .init(projectPath: path, target: target)
    }
}
