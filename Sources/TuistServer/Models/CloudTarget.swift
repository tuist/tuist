import Foundation
import TSCBasic

/// Cloud project
public struct CloudTarget: Codable {
    public init(
        hash: String,
        projectRelativePath: RelativePath,
        targetName: String
    ) {
        self.hash = hash
        self.projectRelativePath = projectRelativePath
        self.targetName = targetName
    }

    public let hash: String
    public let projectRelativePath: RelativePath
    public let targetName: String
}

extension Components.Schemas.Target {
    init(_ target: CloudTarget) {
        hash = target.hash
        project_relative_path = target.projectRelativePath.pathString
        target_name = target.targetName
    }
}
