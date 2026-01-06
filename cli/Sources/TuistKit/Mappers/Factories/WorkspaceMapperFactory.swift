import Foundation
import TSCUtility
import TuistCore
import TuistDependencies
import TuistGenerator
import XcodeGraph
#if canImport(TuistCacheEE)
    import TuistCacheEE
#endif

protocol WorkspaceMapperFactorying {
    /// Returns the default workspace mapper.
    /// - Returns: A workspace mapping instance.
    func `default`(
        tuist: Tuist
    ) -> [WorkspaceMapping]

    /// Returns a mapper for automation commands like build and test.
    /// - Parameter config: The project configuration.
    /// - Returns: A workspace mapping instance.
    func automation(
        tuist: Tuist
    ) -> [WorkspaceMapping]
}

public final class WorkspaceMapperFactory: WorkspaceMapperFactorying {
    private let projectMapper: ProjectMapping

    public init(projectMapper: ProjectMapping) {
        self.projectMapper = projectMapper
    }

    func automation(
        tuist: Tuist
    ) -> [WorkspaceMapping] {
        var mappers: [WorkspaceMapping] = []
        mappers += self.default(
            tuist: tuist
        )

        return mappers
    }

    public func `default`(
        tuist _: Tuist
    ) -> [WorkspaceMapping] {
        var mappers: [WorkspaceMapping] = []

        mappers.append(
            ProjectWorkspaceMapper(mapper: projectMapper)
        )

        mappers.append(
            TuistWorkspaceIdentifierMapper()
        )

        mappers.append(
            TuistWorkspaceRenderMarkdownReadmeMapper()
        )

        mappers.append(
            IDETemplateMacrosMapper()
        )

        mappers.append(
            LastUpgradeVersionWorkspaceMapper()
        )

        mappers.append(ExternalDependencyPathWorkspaceMapper())

        return mappers
    }
}

#if canImport(TuistCacheEE)
    protocol CacheWorkspaceMapperFactorying {
        /// Returns the default workspace mapper.
        /// - Returns: A workspace mapping instance.
        func `default`(tuist: Tuist) -> [WorkspaceMapping]

        /// Generates a list of workspacer mappers to run when pre-loading the graph for cache warming.
        /// - Returns: An array with all the workspace mappers.
        func binaryCacheWarmingPreload(tuist: Tuist) -> [WorkspaceMapping]

        /// Returns a mapper to generate cacheable projects.
        /// - Parameter config: The project configuration.
        /// - Returns: A workspace mapping instance.
        func binaryCacheWarming(tuist: Tuist) -> [WorkspaceMapping]

        /// Returns a mapper for automation commands like build and test.
        /// - Parameter config: The project configuration.
        /// - Returns: A workspace mapping instance.
        func automation(tuist: Tuist) -> [WorkspaceMapping]
    }

    public final class CacheWorkspaceMapperFactory: CacheWorkspaceMapperFactorying {
        private let projectMapper: ProjectMapping

        public init(projectMapper: ProjectMapping) {
            self.projectMapper = projectMapper
        }

        func binaryCacheWarmingPreload(tuist: Tuist) -> [WorkspaceMapping] {
            let mappers = TuistKit.WorkspaceMapperFactory(projectMapper: projectMapper).default(
                tuist: tuist
            )
            return mappers
        }

        func binaryCacheWarming(tuist: Tuist) -> [WorkspaceMapping] {
            TuistKit.WorkspaceMapperFactory(projectMapper: projectMapper).default(
                tuist: tuist
            )
        }

        func automation(tuist: Tuist) -> [WorkspaceMapping] {
            var mappers: [WorkspaceMapping] = []
            mappers += TuistKit.WorkspaceMapperFactory(projectMapper: projectMapper).default(
                tuist: tuist
            )

            return mappers
        }

        func `default`(tuist: Tuist) -> [WorkspaceMapping] {
            TuistKit.WorkspaceMapperFactory(projectMapper: projectMapper).default(tuist: tuist)
        }
    }

#endif
