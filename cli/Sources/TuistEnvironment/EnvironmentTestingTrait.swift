import Foundation
import Path
import Testing

/// A testing trait for mocking the Environment
public struct EnvironmentTestingTrait: TestTrait, SuiteTrait, TestScoping {
    let temporaryDirectory: AbsolutePath?
    let inheritedVariables: [String]
    let arguments: [String]
    let legacyModuleCache: Bool?

    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        let mockEnvironment = try MockEnvironment(temporaryDirectory: temporaryDirectory)
        mockEnvironment.variables = ProcessInfo.processInfo.environment
            .filter { inheritedVariables.contains($0.key) }
        mockEnvironment.arguments = arguments
        if let legacyModuleCache {
            mockEnvironment.variables["TUIST_LEGACY_MODULE_CACHE"] = legacyModuleCache ? "1" : "0"
        }
        try await Environment.$current.withValue(mockEnvironment) {
            try await function()
        }
    }
}

extension Trait where Self == EnvironmentTestingTrait {
    /// When this trait is applied to a test, the environment will be mocked.
    public static func withMockedEnvironment(
        temporaryDirectory: AbsolutePath? = nil,
        inheritingVariables inheritedVariables: [String] = [],
        arguments: [String] = [],
        legacyModuleCache: Bool? = nil
    ) -> Self {
        Self(
            temporaryDirectory: temporaryDirectory,
            inheritedVariables: inheritedVariables,
            arguments: arguments,
            legacyModuleCache: legacyModuleCache
        )
    }
}
