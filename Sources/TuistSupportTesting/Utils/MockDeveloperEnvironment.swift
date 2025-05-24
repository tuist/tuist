import Path
import Testing
import TuistSupport

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

extension DeveloperEnvironment {
    public static var mocked: MockDeveloperEnvironment? { current as? MockDeveloperEnvironment }
}

public struct DeveloperEnvironmentTestingTrait: TestTrait, SuiteTrait, TestScoping {
    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await DeveloperEnvironment.$current.withValue(MockDeveloperEnvironment()) {
            try await function()
        }
    }
}

extension Trait where Self == DeveloperEnvironmentTestingTrait {
    /// When this trait is applied to a test, the environment will be mocked.
    public static var withMockedDeveloperEnvironment: Self { Self() }
}
