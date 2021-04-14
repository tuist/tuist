import Foundation
import TSCBasic
@testable import TuistSupport

public final class MockDeveloperEnvironment: DeveloperEnvironmenting {
    public init() {}

    public var invokedDerivedDataDirectoryGetter = false
    public var invokedDerivedDataDirectoryGetterCount = 0
    public var stubbedDerivedDataDirectory: AbsolutePath!

    public var derivedDataDirectory: AbsolutePath {
        invokedDerivedDataDirectoryGetter = true
        invokedDerivedDataDirectoryGetterCount += 1
        return stubbedDerivedDataDirectory
    }
}
