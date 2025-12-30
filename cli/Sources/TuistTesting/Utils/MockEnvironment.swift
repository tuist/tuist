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
        stateDirectory = directory.path.appending(component: "state")
        cacheDirectory = directory.path.appending(component: ".cache")
        homeDirectory = directory.path.appending(components: "home")
    }

    public var processId: String = UUID().uuidString
    public var isJSONOutput: Bool = false
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
    public var currentExecutablePathStub: AbsolutePath?
    public func currentExecutablePath() -> AbsolutePath? { currentExecutablePathStub ?? Environment.currentExecutablePath() }

    public var homeDirectory: AbsolutePath

    public func derivedDataDirectory() async throws -> Path.AbsolutePath {
        directory.path.appending(components: "DerivedData")
    }

    public var stubbedArchitecture: TuistSupport.MacArchitecture = .arm64
    public func architecture() async throws -> TuistSupport.MacArchitecture {
        return stubbedArchitecture
    }

    public func currentWorkingDirectory() async throws -> AbsolutePath {
        directory.path.appending(components: "current")
    }

    public var cacheDirectory: AbsolutePath

    public var stateDirectory: AbsolutePath

    public var configDirectory: AbsolutePath {
        directory.path.appending(component: "config")
    }

    public var queueDirectory: AbsolutePath {
        queueDirectoryStub ?? directory.path.appending(component: "Queue")
    }

    public func cacheSocketPath(for fullHandle: String) -> AbsolutePath {
        stateDirectory.appending(component: "\(fullHandle.replacingOccurrences(of: "/", with: "_")).sock")
    }

    public func cacheSocketPathString(for fullHandle: String) -> String {
        "$HOME/\(fullHandle).sock"
    }
}

extension Environment {
    public static var mocked: MockEnvironment? { current as? MockEnvironment }
}

public struct EnvironmentTestingTrait: TestTrait, SuiteTrait, TestScoping {
    let temporaryDirectory: AbsolutePath?
    let inheritedVariables: [String]
    let arguments: [String]

    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        let mockEnvironment = try MockEnvironment(temporaryDirectory: temporaryDirectory)
        mockEnvironment.variables = ProcessInfo.processInfo.environment.filter { inheritedVariables.contains($0.key) }
        mockEnvironment.arguments = arguments
        try await Environment.$current.withValue(mockEnvironment) {
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
    public static func withMockedEnvironment(
        temporaryDirectory: AbsolutePath? = nil,
        inheritingVariables inheritedVariables: [String] = [],
        arguments: [String] = []
    ) -> Self {
        Self(temporaryDirectory: temporaryDirectory, inheritedVariables: inheritedVariables, arguments: arguments)
    }
}
