import Foundation

/// Cloud project
public struct CloudProject {
    public let id: Int
    public let slug: String
}

extension CloudProject {
    init(_ project: Components.Schemas.Project) {
        self.id = Int(project.id)
        self.slug = project.slug
    }
}
