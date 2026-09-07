import Mockable
import Path
import TuistConfig
import TuistCore
import TuistGenerator
import TuistLoader
import TuistLogging
import XcodeGraph

@Mockable
public protocol ProjectGraphLoading {
    func load(path: AbsolutePath, config: Tuist) async throws -> Graph
}

public struct ProjectGraphLoader: ProjectGraphLoading {
    private let manifestLoader: ManifestLoading

    public init(manifestLoader: ManifestLoading = ManifestLoader.current) {
        self.manifestLoader = manifestLoader
    }

    public func load(path: AbsolutePath, config: Tuist) async throws -> Graph {
        let projectMappers = DefaultProjectMapperFactory().make(tuist: config)
        let workspaceMappers = DefaultWorkspaceMapperFactory(
            projectMapper: SequentialProjectMapper(mappers: projectMappers)
        ).make(tuist: config)
        let graphMappers = DefaultGraphMapperFactory().makeForAutomation(
            config: config,
            testPlan: nil,
            includedTargets: [],
            excludedTargets: []
        )

        Logger.current.notice("Loading and constructing the graph", metadata: .section)
        Logger.current.notice("It might take a while if the cache is empty")

        let (graph, _, _, _) = try await ManifestGraphLoader(
            manifestLoader: manifestLoader,
            workspaceMapper: SequentialWorkspaceMapper(mappers: workspaceMappers),
            graphMapper: SequentialGraphMapper(graphMappers)
        ).load(
            path: path,
            disableSandbox: config.project.generatedProject?.generationOptions.disableSandbox ?? true
        )
        return graph
    }
}
