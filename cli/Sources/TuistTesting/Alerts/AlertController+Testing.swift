import Testing
import TuistSupport

extension AlertController {
    @TaskLocal public static var testingAlertController: AlertController = .init()
}

public struct AlertControllerTestingTrait: TestTrait, SuiteTrait, TestScoping {
    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await AlertController.$current.withValue(AlertController()) {
            try await function()
        }
    }
}

extension Trait where Self == AlertControllerTestingTrait {
    /// Scopes the alert controller to the test using this trait.
    public static func withScopedAlertController() -> Self {
        return Self()
    }
}
