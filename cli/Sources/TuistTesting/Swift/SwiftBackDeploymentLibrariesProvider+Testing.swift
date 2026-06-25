import Testing
import TuistSupport

/// Returns a fixed `swift-6.2` run path so SPM target expectations stay deterministic across toolchains.
private struct StubbedSwiftBackDeploymentLibrariesProvider: SwiftBackDeploymentLibrariesProviding {
    func runpathSearchPaths() async throws -> [String] {
        ["$(TOOLCHAIN_DIR)/usr/lib/swift-6.2/$(PLATFORM_NAME)"]
    }
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
    /// When applied to a test, a stubbed back-deployment libraries provider returning a fixed
    /// `swift-6.2` run path is used so expectations stay deterministic across toolchains.
    public static var withMockedSwiftBackDeploymentLibrariesProvider: Self { Self() }
}
