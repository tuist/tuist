import Testing
import TuistSupport

public struct SwiftBackDeploymentLibrariesProviderTestingTrait: TestTrait, SuiteTrait, TestScoping {
    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await SwiftBackDeploymentLibrariesProvider.$current.withValue(MockSwiftBackDeploymentLibrariesProviding()) {
            try await function()
        }
    }
}

extension Trait where Self == SwiftBackDeploymentLibrariesProviderTestingTrait {
    /// When this trait is applied to a test, the mocked back-deployment libraries provider will be used.
    public static var withMockedSwiftBackDeploymentLibrariesProvider: Self { Self() }
}
