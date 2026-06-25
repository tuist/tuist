import Testing
import TuistSupport

/// Returns no run paths so SPM target expectations don't depend on the test machine's toolchain.
/// Tests that exercise the run-path behavior stub their own provider with a value.
private struct StubbedSwiftBackDeploymentLibrariesProvider: SwiftBackDeploymentLibrariesProviding {
    func runpathSearchPaths() async throws -> [String] { [] }
}

public struct SwiftBackDeploymentLibrariesProviderTestingTrait: TestTrait, SuiteTrait, TestScoping {
    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await SwiftBackDeploymentLibrariesProvider.$current.withValue(StubbedSwiftBackDeploymentLibrariesProvider()) {
            try await function()
        }
    }
}

extension Trait where Self == SwiftBackDeploymentLibrariesProviderTestingTrait {
    /// When applied to a test, a stubbed back-deployment libraries provider returning no run paths
    /// is used so SPM target expectations don't depend on the test machine's toolchain.
    public static var withMockedSwiftBackDeploymentLibrariesProvider: Self { Self() }
}
