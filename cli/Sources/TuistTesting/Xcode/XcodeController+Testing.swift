import Testing
import TuistSupport

extension XcodeController {
    public static var mocked: MockXcodeControlling? { current as? MockXcodeControlling }
}

public struct XcodeControllerTestingTrait: TestTrait, SuiteTrait, TestScoping {
    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await XcodeController.$current.withValue(MockXcodeControlling()) {
            try await function()
        }
    }
}

public func withMockedXcodeController<T>(_ function: () async throws -> T) async throws -> T {
    return try await XcodeController.$current.withValue(MockXcodeControlling()) {
        try await function()
    }
}

extension Trait where Self == XcodeControllerTestingTrait {
    /// When this trait is applied to a test, the mocked Xcode controller will be used.
    public static var withMockedXcodeController: Self { Self() }
}
