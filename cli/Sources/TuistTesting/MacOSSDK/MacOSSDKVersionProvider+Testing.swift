import Testing
import TuistMacOSSDK

public struct MacOSSDKVersionProviderTestingTrait: TestTrait, SuiteTrait, TestScoping {
    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await MacOSSDKVersionProvider.$current.withValue(MockMacOSSDKVersionProviding()) {
            try await function()
        }
    }
}

extension Trait where Self == MacOSSDKVersionProviderTestingTrait {
    /// When this trait is applied to a test, the mocked macOS SDK version provider will be used.
    public static var withMockedMacOSSDKVersionProvider: Self { Self() }
}
