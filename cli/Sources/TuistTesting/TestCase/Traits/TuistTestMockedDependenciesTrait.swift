import Testing

public struct TuistTestMockedDependenciesTrait: TestTrait, SuiteTrait, TestScoping {
    let forwardingLogs: Bool

    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await _withMockedDependencies(forwardLogs: forwardingLogs) {
            try await function()
        }
    }
}

extension Trait where Self == TuistTestMockedDependenciesTrait {
    public static func withMockedDependencies(forwardingLogs: Bool = false) -> Self {
        return Self(forwardingLogs: forwardingLogs)
    }
}
