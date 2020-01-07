import Basic
import Foundation

public struct TargetReference: Hashable {
    public var projectPath: AbsolutePath
    public var name: String

    public static func project(path: AbsolutePath, target: String) -> TargetReference {
        .init(projectPath: path, name: target)
    }

    public init(projectPath: AbsolutePath, name: String) {
        self.projectPath = projectPath
        self.name = name
    }
}
