import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

@testable import TuistLoader

// swiftlint:disable:next type_name
public final class MockHelpersBuilderFactory: HelpersBuilderFactoring {
    public var projectAutomationHelpersBuilderStub: ((AbsolutePath) -> HelpersBuilding)!
    public func helpersBuilder(cacheDirectory: AbsolutePath) -> HelpersBuilding {
        projectAutomationHelpersBuilderStub(cacheDirectory)
    }
    
    public var projectDescriptionHelpersBuilderStub: ((AbsolutePath) -> HelpersBuilding)!
    public func projectDescriptionHelpersBuilder(cacheDirectory: AbsolutePath) -> HelpersBuilding {
        projectDescriptionHelpersBuilderStub(cacheDirectory)
    }
}
