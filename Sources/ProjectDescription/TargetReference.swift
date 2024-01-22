import Foundation

/// A target reference for a specified project.
///
/// The project is specified through the path and should contain the target name.
public struct TargetReference: Hashable, Codable, ExpressibleByStringInterpolation {
    /// Path to the target's project directory.
    public var projectPath: Path?
    /// Name of the target.
    public var targetName: String
}

extension TargetReference: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self = .init(projectPath: nil, target: value)
    }
}
