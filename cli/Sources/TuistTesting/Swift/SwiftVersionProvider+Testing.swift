import Testing
import TuistSupport

extension SwiftVersionProvider {
    public static var mocked: MockSwiftVersionProviding? { current as? MockSwiftVersionProviding }
}

public struct SwiftVersionProviderTestingTrait: TestTrait, SuiteTrait, TestScoping {
    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await SwiftVersionProvider.$current.withValue(MockSwiftVersionProviding()) {
            try await function()
        }
    }
}

extension Trait where Self == SwiftVersionProviderTestingTrait {
    /// When this trait is applied to a test, the mocked swift version provider will be used.
    public static var withMockedSwiftVersionProvider: Self { Self() }
}
