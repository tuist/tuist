import Foundation
import Path
import TuistSupport

// swiftlint:disable:next type_name
public protocol ProjectDescriptionHelpersBuilderFactoring {
    func projectDescriptionHelpersBuilder(cacheDirectory: AbsolutePath) -> ProjectDescriptionHelpersBuilding
}

public final class ProjectDescriptionHelpersBuilderFactory: ProjectDescriptionHelpersBuilderFactoring {
    public init() {}

    private var helperBuildersCache: ThreadSafe<[AbsolutePath: ProjectDescriptionHelpersBuilding]> = ThreadSafe([:])

    public func projectDescriptionHelpersBuilder(cacheDirectory: AbsolutePath) -> any ProjectDescriptionHelpersBuilding {
        return helperBuildersCache.mutate { builders in
            if let helpersBuilder = builders[cacheDirectory] {
                return helpersBuilder
            } else {
                let newBuilder = ProjectDescriptionHelpersBuilder(cacheDirectory: cacheDirectory)
                builders[cacheDirectory] = newBuilder
                return newBuilder
            }
        }
    }
}

#if DEBUG
    // swiftlint:disable:next type_name
    public final class MockProjectDescriptionHelpersBuilderFactory: ProjectDescriptionHelpersBuilderFactoring {
        public var projectDescriptionHelpersBuilderStub: ((AbsolutePath) -> ProjectDescriptionHelpersBuilding)!

        public init() {}

        public func projectDescriptionHelpersBuilder(cacheDirectory: AbsolutePath) -> ProjectDescriptionHelpersBuilding {
            projectDescriptionHelpersBuilderStub(cacheDirectory)
        }
    }
#endif
