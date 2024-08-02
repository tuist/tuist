import Foundation
import Path
import TuistSupport
import XcodeGraph

/// CachedProjectDescriptionHelpersBuilderFactory
///
/// is a wrapper on top of `ProjectDescriptionHelpersBuilderFactory` that adds an in-memory cache
/// to avoid re-creating builder for same cacheDirectory
// swiftlint:disable:next type_name
public final class CachedProjectDescriptionHelpersBuilderFactory: ProjectDescriptionHelpersBuilderFactoring {
    public init(
        builderFactory: any ProjectDescriptionHelpersBuilderFactoring = ProjectDescriptionHelpersBuilderFactory()
    ) {
        self.builderFactory = builderFactory
    }

    private let builderFactory: ProjectDescriptionHelpersBuilderFactoring
    private var helperBuildersCache: ThreadSafe<[AbsolutePath: ProjectDescriptionHelpersBuilding]> = ThreadSafe([:])

    public func projectDescriptionHelpersBuilder(cacheDirectory: AbsolutePath) -> any ProjectDescriptionHelpersBuilding {
        return helperBuildersCache.mutate { builders in
            if let helpersBuilder = builders[cacheDirectory] {
                return helpersBuilder
            } else {
                let newBuilder = builderFactory.projectDescriptionHelpersBuilder(cacheDirectory: cacheDirectory)
                builders[cacheDirectory] = newBuilder
                return newBuilder
            }
        }
    }
}
