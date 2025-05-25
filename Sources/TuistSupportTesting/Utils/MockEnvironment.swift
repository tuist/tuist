import Foundation
import Path
import Testing
import TuistSupport
import XCTest

public final class MockEnvironment: Environmenting {
    enum Directory {
        case owned(TemporaryDirectory)
        case notowned(AbsolutePath)
        var path: AbsolutePath {
            switch self {
            case let .owned(directory): return directory.path
            case let .notowned(path): return path
            }
        }
    }

    fileprivate let directory: Directory

    init(temporaryDirectory: AbsolutePath? = nil) throws {
        if let temporaryDirectory {
            directory = .notowned(temporaryDirectory)
        } else {
            directory = .owned(try TemporaryDirectory(removeTreeOnDeinit: true))
        }
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
    public var workspacePath: AbsolutePath?
    public var schemeName: String?
    public func currentExecutablePath() -> AbsolutePath? { Environment.currentExecutablePath() }

    public var cacheDirectory: AbsolutePath {
        directory.path.appending(components: ".cache")
    }

    public var stateDirectory: AbsolutePath {
        directory.path.appending(component: "state")
    }

    public var configDirectory: AbsolutePath {
        directory.path.appending(component: "state")
    }

    public var queueDirectory: AbsolutePath {
        queueDirectoryStub ?? directory.path.appending(component: "Queue")
    }
}

extension Environment {
    public static var mocked: MockEnvironment? { current as? MockEnvironment }
}

public struct EnvironmentTestingTrait: TestTrait, SuiteTrait, TestScoping {
    let temporaryDirectory: AbsolutePath?

    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await Environment.$current.withValue(MockEnvironment(temporaryDirectory: temporaryDirectory)) {
            try await function()
        }
    }
}

public func withMockedEnvironment(temporaryDirectory: AbsolutePath? = nil, _ closure: () async throws -> Void) async throws {
    try await Environment.$current.withValue(MockEnvironment(temporaryDirectory: temporaryDirectory)) {
        try await closure()
    }
}

extension Trait where Self == EnvironmentTestingTrait {
    /// When this trait is applied to a test, the environment will be mocked.
    public static func withMockedEnvironment(temporaryDirectory: AbsolutePath? = nil) -> Self {
        Self(temporaryDirectory: temporaryDirectory)
    }
}
