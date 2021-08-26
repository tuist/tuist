import Foundation
import TuistCore
import TuistGraph

class GenerateCacheableSchemesWorkspaceMapperProvider: WorkspaceMapperProviding { // swiftlint:disable:this type_name
    private let workspaceMapperProvider: WorkspaceMapperProviding
    private let includedTargets: [Target]

    init(workspaceMapperProvider: WorkspaceMapperProviding,
         includedTargets: [Target])
    {
        self.workspaceMapperProvider = workspaceMapperProvider
        self.includedTargets = includedTargets
    }

    func mapper(config: Config) -> WorkspaceMapping {
        SequentialWorkspaceMapper(
            mappers: [
                workspaceMapperProvider.mapper(config: config),
                GenerateCacheableSchemesWorkspaceMapper(includedTargets: includedTargets),
            ]
        )
    }
}
