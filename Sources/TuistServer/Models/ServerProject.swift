import Foundation

/// Server project
public struct ServerProject: Codable {
    public init(
        id: Int,
        fullName: String,
        defaultBranch: String,
        repositoryURL: String?
    ) {
        self.id = id
        self.fullName = fullName
        self.defaultBranch = defaultBranch
        self.repositoryURL = repositoryURL
    }

    public let id: Int
    public let fullName: String
    public let defaultBranch: String
    public let repositoryURL: String?
}

extension ServerProject {
    init(_ project: Components.Schemas.Project) {
        id = Int(project.id)
        fullName = project.full_name
        defaultBranch = project.default_branch
        repositoryURL = project.repository_url
    }
}

#if MOCKING
    extension ServerProject {
        public static func test(
            id: Int = 0,
            fullName: String = "test/test",
            defaultBranch: String = "main",
            repositoryURL: String? = nil
        ) -> Self {
            .init(
                id: id,
                fullName: fullName,
                defaultBranch: defaultBranch,
                repositoryURL: repositoryURL
            )
        }
    }
#endif
