import Testing
import TuistSupport

extension RecentPathsStore {
    public static var mocked: MockRecentPathsStoring? { current as? MockRecentPathsStoring }
}

public struct RecentPathsStoreTestingTrait: TestTrait, SuiteTrait, TestScoping {
    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await RecentPathsStore.$current.withValue(MockRecentPathsStoring()) {
            try await function()
        }
    }
}

extension Trait where Self == RecentPathsStoreTestingTrait {
    /// When this trait is applied, it uses a mock for the task local `RecentPathsStore.current`.`
    public static var withMockedRecentPathsStore: Self { Self() }
}
