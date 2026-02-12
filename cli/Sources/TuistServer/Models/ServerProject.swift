import Foundation

/// Server project
public struct ServerProject: Codable, Identifiable {
    public enum Visibility: String, Codable {
        case `public`, `private`
    }

    public enum BuildSystem: String, Codable, CaseIterable, CustomStringConvertible, Equatable {
        case xcode, gradle

        public var description: String {
            switch self {
            case .xcode: "Xcode"
            case .gradle: "Gradle"
            }
        }
    }

    public init(
        id: Int,
        fullName: String,
        defaultBranch: String,
        repositoryURL: String?,
        visibility: Visibility,
        buildSystem: BuildSystem
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
    public let buildSystem: BuildSystem
}

extension ServerProject {
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
        buildSystem = switch project.build_system {
        case .gradle:
            .gradle
        case .xcode, nil:
            .xcode
        }
    }
}

extension ServerProject: CustomStringConvertible {
    public var description: String {
        fullName
    }
}

#if MOCKING
    extension ServerProject {
        public static func test(
            id: Int = 0,
            fullName: String = "test/test",
            defaultBranch: String = "main",
            repositoryURL: String? = nil,
            visibility: Visibility = .private,
            buildSystem: BuildSystem = .xcode
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
    }
#endif
