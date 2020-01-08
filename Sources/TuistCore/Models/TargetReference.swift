import Basic
import Foundation

public struct TargetReference: Hashable {
    public var projectPath: AbsolutePath
    public var name: String

    public init(projectPath: AbsolutePath, name: String) {
        self.projectPath = projectPath
        self.name = name
    }
}
