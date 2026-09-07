import Foundation
import TSCUtility
import TuistConfig
import TuistCore
import TuistDependencies
import TuistGenerator
import TuistGraphLoader
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

public struct WorkspaceMapperFactory: WorkspaceMapperFactorying {
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
        tuist: Tuist
    ) -> [WorkspaceMapping] {
        DefaultWorkspaceMapperFactory(projectMapper: projectMapper).make(tuist: tuist)
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

    public struct CacheWorkspaceMapperFactory: CacheWorkspaceMapperFactorying {
        private let projectMapper: ProjectMapping

        public init(projectMapper: ProjectMapping) {
            self.projectMapper = projectMapper
        }

        func binaryCacheWarmingPreload(tuist: Tuist) -> [WorkspaceMapping] {
            return TuistKit.WorkspaceMapperFactory(projectMapper: projectMapper).default(
                tuist: tuist
            )
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
