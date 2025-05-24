import Foundation
import Path
import Testing
import TuistSupport
import XCTest

public final class MockEnvironment: Environmenting {
    fileprivate let directory: TemporaryDirectory

    init() throws {
        directory = try TemporaryDirectory(removeTreeOnDeinit: true)
    }

    public var isVerbose: Bool = false
    public var queueDirectoryStub: AbsolutePath?
    public var shouldOutputBeColoured: Bool = false
    public var isStandardOutputInteractive: Bool = false
    public var manifestLoadingVariables: [String: String] = [:]
    public var isStatsEnabled: Bool = true
    public var isGitHubActions: Bool = false
    public var variables: [String: String] = [:]
    public var arguments: [String] = []

    public var cacheDirectory: AbsolutePath {
        directory.path.appending(components: ".cache")
    }

    public var stateDirectory: AbsolutePath {
        directory.path.appending(component: "state")
    }

    public var queueDirectory: AbsolutePath {
        queueDirectoryStub ?? directory.path.appending(component: Constants.AsyncQueue.directoryName)
    }

    public var workspacePath: AbsolutePath?

    public var schemeName: String?

    public func currentExecutablePath() -> AbsolutePath? { nil }
}

extension Environment {
    public static var mocked: MockEnvironment? { current as? MockEnvironment }
}

public struct EnvironmentTestingTrait: TestTrait, SuiteTrait, TestScoping {
    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await Environment.$current.withValue(MockEnvironment()) {
            try await function()
        }
    }
}

public func withMockedEnvironment(_ closure: () async throws -> Void) async throws {
    try await Environment.$current.withValue(MockEnvironment()) {
        try await closure()
    }
}

extension Trait where Self == EnvironmentTestingTrait {
    /// When this trait is applied to a test, the environment will be mocked.
    public static var withMockedEnvironment: Self { Self() }
}
