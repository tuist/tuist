import Foundation

/// Cloud project
public struct CloudProject: Codable {
    public init(
        id: Int,
        fullName: String
    ) {
        self.id = id
        self.fullName = fullName
    }

    public let id: Int
    public let fullName: String
}

extension CloudProject {
    init(_ project: Components.Schemas.Project) {
        id = Int(project.id)
        fullName = project.full_name
    }
}
