import Foundation
import TSCBasic

public struct TargetReference: Hashable, Codable {
    public var projectPath: AbsolutePath
    public var name: String

    public init(projectPath: AbsolutePath, name: String) {
        self.projectPath = projectPath
        self.name = name
    }
}
