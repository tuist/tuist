import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

public protocol HelpersBuilderFactoring {
    func helpersBuilder(cacheDirectory: AbsolutePath) -> HelpersBuilding
}

public final class HelpersBuilderFactory: HelpersBuilderFactoring {
    public init() {}
    public func helpersBuilder(cacheDirectory: AbsolutePath) -> HelpersBuilding {
        HelpersBuilder(cacheDirectory: cacheDirectory)
    }
}
