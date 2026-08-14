import Testing
import TuistSupport

public struct SDKDeploymentTargetsProviderTestingTrait: TestTrait, SuiteTrait, TestScoping {
    /// Scopes the mock to each test so that tests stubbing their own deployment targets don't leak into others.
    public var isRecursive: Bool { true }

    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await SDKDeploymentTargetsProvider.$current.withValue(MockSDKDeploymentTargetsProviding()) {
            try await function()
        }
    }
}

extension Trait where Self == SDKDeploymentTargetsProviderTestingTrait {
    /// When this trait is applied to a test, the mocked SDK deployment targets provider will be used.
    public static var withMockedSDKDeploymentTargetsProvider: Self { Self() }
}
