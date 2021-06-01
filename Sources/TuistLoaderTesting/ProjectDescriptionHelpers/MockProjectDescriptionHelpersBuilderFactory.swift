import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

@testable import TuistLoader

// swiftlint:disable:next type_name
public final class MockProjectDescriptionHelpersBuilderFactory: ProjectDescriptionHelpersBuilderFactoring {
    public var projectDescriptionHelpersBuilderStub: ((AbsolutePath) -> ProjectDescriptionHelpersBuilding)!
    public func projectDescriptionHelpersBuilder(cacheDirectory: AbsolutePath) -> ProjectDescriptionHelpersBuilding {
        projectDescriptionHelpersBuilderStub(cacheDirectory)
    }
}
