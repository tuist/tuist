import Foundation

/// Server project
public struct ServerProject: Codable, Identifiable, CustomStringConvertible {
    public enum Visibility: String, Codable {
        case `public`, `private`
    }

    public init(
        id: Int,
        fullName: String,
        defaultBranch: String,
        repositoryURL: String?,
        visibility: Visibility,
        buildSystem: Components.Schemas.Project.build_systemPayload
    ) {
        self.id = id
        self.fullName = fullName
        self.defaultBranch = defaultBranch
        self.repositoryURL = repositoryURL
        self.visibility = visibility
        self.buildSystem = buildSystem
    }

    public let id: Int
    public let fullName: String
    public let defaultBranch: String
    public let repositoryURL: String?
    public let visibility: Visibility
    public let buildSystem: Components.Schemas.Project.build_systemPayload

    init(_ project: Components.Schemas.Project) {
        id = Int(project.id)
        fullName = project.full_name
        defaultBranch = project.default_branch
        repositoryURL = project.repository_url
        visibility = switch project.visibility {
        case ._private:
            .private
        case ._public:
            .public
        }
        buildSystem = project.build_system ?? .xcode
    }

    #if MOCKING
        public static func test(
            id: Int = 0,
            fullName: String = "test/test",
            defaultBranch: String = "main",
            repositoryURL: String? = nil,
            visibility: Visibility = .private,
            buildSystem: Components.Schemas.Project.build_systemPayload = .xcode
        ) -> Self {
            .init(
                id: id,
                fullName: fullName,
                defaultBranch: defaultBranch,
                repositoryURL: repositoryURL,
                visibility: visibility,
                buildSystem: buildSystem
            )
        }
    #endif

    public var description: String {
        fullName
    }
}
