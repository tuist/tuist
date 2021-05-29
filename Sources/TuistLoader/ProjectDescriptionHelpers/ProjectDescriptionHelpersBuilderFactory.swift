import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

public protocol ProjectDescriptionHelpersBuilderFactoring {
    func projectDescriptionHelpersBuilder(cacheDirectory: AbsolutePath) -> ProjectDescriptionHelpersBuilding
}

public final class ProjectDescriptionHelpersBuilderFactory: ProjectDescriptionHelpersBuilderFactoring {
    public init() {}
    public func projectDescriptionHelpersBuilder(cacheDirectory: AbsolutePath) -> ProjectDescriptionHelpersBuilding {
        ProjectDescriptionHelpersBuilder(cacheDirectory: cacheDirectory)
    }
}
