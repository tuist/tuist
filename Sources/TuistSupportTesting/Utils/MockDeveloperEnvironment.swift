import Foundation
import TSCBasic
@testable import TuistSupport

public final class MockDeveloperEnvironment: DeveloperEnvironmenting {
    public var invokedDerivedDataDirectoryGetter = false
    public var invokedDerivedDataDirectoryGetterCount = 0
    public var stubbedDerivedDataDirectory: AbsolutePath!

    public var derivedDataDirectory: AbsolutePath {
        invokedDerivedDataDirectoryGetter = true
        invokedDerivedDataDirectoryGetterCount += 1
        return stubbedDerivedDataDirectory
    }

    public var invokedArchitectureGetter = false
    public var invokedArchitectureGetterCount = 0
    public var stubbedArchitecture: MacArchitecture!

    public var architecture: MacArchitecture {
        invokedArchitectureGetter = true
        invokedArchitectureGetterCount += 1
        return stubbedArchitecture
    }
}
