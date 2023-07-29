import Foundation

/// Cloud project
public struct CloudProject {
    public let id: Int
    public let slug: String
}

extension CloudProject {
    init(_ project: Components.Schemas.Project) {
        id = Int(project.id)
        slug = project.slug
    }
}
