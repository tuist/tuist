import Foundation
import TuistCore
import TuistGraph

class GenerateCacheableSchemesWorkspaceMapperProvider: WorkspaceMapperProviding { // swiftlint:disable:this type_name
    private let workspaceMapperProvider: WorkspaceMapperProviding
    private let includedTargets: Set<String>

    init(workspaceMapperProvider: WorkspaceMapperProviding,
         includedTargets: Set<String>)
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
