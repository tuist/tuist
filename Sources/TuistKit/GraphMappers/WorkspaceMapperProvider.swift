import Foundation
import TuistCore

protocol WorkspaceMapperProviding {
    func mapper(config: Config) -> WorkspaceMapping
}

final class WorkspaceMapperProvider: WorkspaceMapperProviding {
    private let projectMapperProvider: ProjectMapperProviding
    init(projectMapperProvider: ProjectMapperProviding = ProjectMapperProvider()) {
        self.projectMapperProvider = projectMapperProvider
    }

    func mapper(config: Config) -> WorkspaceMapping {
        var mappers: [WorkspaceMapping] = []

        mappers.append(
            ProjectWorkspaceMapper(mapper: projectMapperProvider.mapper(config: config))
        )

        mappers.append(
            TuistWorkspaceIdentifierMapper()
        )

        return SequentialWorkspaceMapper(mappers: mappers)
    }
}
