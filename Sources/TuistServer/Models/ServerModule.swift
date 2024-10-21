import Foundation
import Path

/// Server module
public struct ServerModule: Codable {
    public init(
        hash: String,
        projectRelativePath: RelativePath,
        name: String
    ) {
        self.hash = hash
        self.projectRelativePath = projectRelativePath
        self.name = name
    }

    public let hash: String
    public let projectRelativePath: RelativePath
    public let name: String
}

extension Components.Schemas.Module {
    init(_ module: ServerModule) {
        hash = module.hash
        project_identifier = module.projectRelativePath.pathString
        name = module.name
    }
}
