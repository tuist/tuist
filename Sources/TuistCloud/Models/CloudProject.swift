import Foundation

/// Cloud project
public struct CloudProject: Codable {
    public init(
        id: Int,
        fullName: String,
        token: String
    ) {
        self.id = id
        self.fullName = fullName
        self.token = token
    }

    public let id: Int
    public let fullName: String
    public let token: String
}

extension CloudProject {
    init(_ project: Components.Schemas.Project) {
        id = Int(project.id)
        fullName = project.full_name
        token = project.token
    }
}
