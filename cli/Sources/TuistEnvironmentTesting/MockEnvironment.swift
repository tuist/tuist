import Foundation
import Path
import Testing
import TuistEnvironment

public final class MockEnvironment: Environmenting, @unchecked Sendable {
    private let baseDirectory: AbsolutePath

    public init() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let uniqueDir = tempDir.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: uniqueDir, withIntermediateDirectories: true)
        baseDirectory = try AbsolutePath(validating: uniqueDir.path)
        stateDirectory = baseDirectory.appending(component: "state")
        cacheDirectory = baseDirectory.appending(component: ".cache")
        homeDirectory = baseDirectory.appending(component: "home")
    }

    deinit {
        try? FileManager.default.removeItem(atPath: baseDirectory.pathString)
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

    public func currentExecutablePath() -> AbsolutePath? {
        currentExecutablePathStub ?? Environment.currentExecutablePath()
    }

    public var homeDirectory: AbsolutePath

    public func derivedDataDirectory() async throws -> Path.AbsolutePath {
        baseDirectory.appending(component: "DerivedData")
    }

    public var stubbedArchitecture: MacArchitecture = .arm64
    public func architecture() async throws -> MacArchitecture {
        stubbedArchitecture
    }

    public func currentWorkingDirectory() async throws -> AbsolutePath {
        baseDirectory.appending(component: "current")
    }

    public var cacheDirectory: AbsolutePath

    public var stateDirectory: AbsolutePath

    public var configDirectory: AbsolutePath {
        baseDirectory.appending(component: "config")
    }

    public var queueDirectory: AbsolutePath {
        queueDirectoryStub ?? baseDirectory.appending(component: "Queue")
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
    let inheritedVariables: [String]
    let arguments: [String]
    let legacyModuleCache: Bool

    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        let mockEnvironment = try MockEnvironment()
        mockEnvironment.variables = ProcessInfo.processInfo.environment.filter { inheritedVariables.contains($0.key) }
        mockEnvironment.arguments = arguments
        if legacyModuleCache {
            mockEnvironment.variables["TUIST_LEGACY_MODULE_CACHE"] = "1"
        }
        try await Environment.$current.withValue(mockEnvironment) {
            try await function()
        }
    }
}

extension Trait where Self == EnvironmentTestingTrait {
    public static func withMockedEnvironment(
        inheritingVariables inheritedVariables: [String] = [],
        arguments: [String] = [],
        legacyModuleCache: Bool = false
    ) -> Self {
        Self(
            inheritedVariables: inheritedVariables,
            arguments: arguments,
            legacyModuleCache: legacyModuleCache
        )
    }
}

public func withMockedEnvironment(
    _ closure: () async throws -> Void
) async throws {
    let mockEnvironment = try MockEnvironment()
    try await Environment.$current.withValue(mockEnvironment) {
        try await closure()
    }
}
