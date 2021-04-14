import Foundation

public struct TargetReference: Equatable, Codable, ExpressibleByStringInterpolation {
    public var projectPath: Path?
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
