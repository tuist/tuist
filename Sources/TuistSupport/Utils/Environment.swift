import Darwin
import FileSystem
import Foundation
import Mockable
import Path
import ServiceContextModule

private enum EnvironmentServiceContextKey: ServiceContextKey {
    typealias Value = Environmenting
}

extension ServiceContext {
    public var environment: Environmenting? {
        get {
            self[EnvironmentServiceContextKey.self]
        } set {
            self[EnvironmentServiceContextKey.self] = newValue
        }
    }
}

/// Protocol that defines the interface of a local environment controller.
/// It manages the local directory where tuistenv stores the tuist versions and user settings.
@Mockable
public protocol Environmenting: Sendable {
    /// Returns true if the output of Tuist should be coloured.
    var shouldOutputBeColoured: Bool { get }

    /// Returns automation path
    /// Only to be used for acceptance tests
    var automationPath: AbsolutePath? { get }

    /// Returns all the environment variables that are specific to Tuist (prefixed with TUIST_)
    var tuistVariables: [String: String] { get }

    /// Returns all the environment variables that can be included during the manifest loading process
    var manifestLoadingVariables: [String: String] { get }

    /// Returns true if Tuist is running with verbose mode enabled.
    var isVerbose: Bool { get }

    /// Returns the path to the cache directory. Configurable via the `XDG_CACHE_HOME` environment variable
    var cacheDirectory: AbsolutePath { get }

    /// Returns the path to the state directory. Configurable via the `XDG_STATE_HOME` environment variable
    var stateDirectory: AbsolutePath { get }

    /// Returns the path to the directory where the async queue events are persisted.
    var queueDirectory: AbsolutePath { get }

    /// Returns true unless the user specifically opted out from stats
    var isStatsEnabled: Bool { get }

    /// Returns true if the environment is a GitHub Actions environment
    var isGitHubActions: Bool { get }

    /// Represents path stored in the `WORKSPACE_PATH` environment variable. This variable is defined in Xcode build actions and
    /// can be used for further processing of a given Xcode project.
    var workspacePath: AbsolutePath? { get }

    /// Represents scheme name stored in the `SCHEME_NAME` environment variable. This variable is defined in Xcode build actions
    /// and can be used for further processing.
    var schemeName: String? { get }

    /// Returns path to the Tuist executable
    func currentExecutablePath() -> AbsolutePath?
}

/// Local environment controller.
public struct Environment: Environmenting {
    // MARK: - Attributes

    /// Default public constructor.
    public init() {}

    // MARK: - EnvironmentControlling

    /// Returns true if the output of Tuist should be coloured.
    public var shouldOutputBeColoured: Bool {
        let noColor =
            if let noColorEnvVariable = ProcessInfo.processInfo.environment["NO_COLOR"] {
                Constants.trueValues.contains(noColorEnvVariable)
            } else {
                false
            }
        let ciColorForce =
            if let ciColorForceEnvVariable = ProcessInfo.processInfo.environment["CLICOLOR_FORCE"] {
                Constants.trueValues.contains(ciColorForceEnvVariable)
            } else {
                false
            }
        if noColor {
            return false
        } else if ciColorForce {
            return true
        } else {
            let isPiped = isatty(fileno(stdout)) == 0
            return !isPiped
        }
    }

    /// Returns true if the environment represents a GitHub Actions environment
    public var isGitHubActions: Bool {
        if let githubActions = ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] {
            return Constants.trueValues.contains(githubActions)
        } else {
            return false
        }
    }

    /// Returns true if the standard output is interactive.
    public var isStandardOutputInteractive: Bool {
        let termType = ProcessInfo.processInfo.environment["TERM"]
        if let t = termType, t.lowercased() != "dumb", isatty(fileno(stdout)) != 0 {
            return true
        }
        return false
    }

    public var isVerbose: Bool {
        guard let variable = ProcessInfo.processInfo.environment[
            Constants.EnvironmentVariables.verbose
        ]
        else { return false }
        return Constants.trueValues.contains(variable)
    }

    public var isStatsEnabled: Bool {
        guard let variable = ProcessInfo.processInfo.environment[
            Constants.EnvironmentVariables.statsOptOut
        ]
        else { return true }
        let userOptedOut = Constants.trueValues.contains(variable)
        return !userOptedOut
    }

    public var cacheDirectory: AbsolutePath {
        let baseCacheDirectory: AbsolutePath
        if let cacheDirectoryPathString = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"],
           let cacheDirectory = try? AbsolutePath(validating: cacheDirectoryPathString)
        {
            baseCacheDirectory = cacheDirectory
        } else {
            // swiftlint:disable:next force_try
            let homeDirectory = try! Path.AbsolutePath(validating: NSHomeDirectory())
            baseCacheDirectory = homeDirectory.appending(components: ".cache")
        }

        return baseCacheDirectory.appending(component: "tuist")
    }

    public var stateDirectory: AbsolutePath {
        let baseStateDirectory: AbsolutePath
        if let stateDirectoryPathString = ProcessInfo.processInfo.environment["XDG_STATE_HOME"],
           let stateDirectory = try? AbsolutePath(validating: stateDirectoryPathString)
        {
            baseStateDirectory = stateDirectory
        } else {
            // swiftlint:disable:next force_try
            let homeDirectory = try! Path.AbsolutePath(validating: NSHomeDirectory())
            baseStateDirectory = homeDirectory.appending(components: [".local", "state"])
        }

        return baseStateDirectory.appending(component: "tuist")
    }

    public var automationPath: AbsolutePath? {
        ProcessInfo.processInfo.environment[Constants.EnvironmentVariables.automationPath]
            .map { try! AbsolutePath(validating: $0) } // swiftlint:disable:this force_try
    }

    public var queueDirectory: AbsolutePath {
        if let envVariable = ProcessInfo.processInfo.environment[
            Constants.EnvironmentVariables.queueDirectory
        ] {
            return try! AbsolutePath(validating: envVariable) // swiftlint:disable:this force_try
        } else {
            return cacheDirectory.appending(component: Constants.AsyncQueue.directoryName)
        }
    }

    /// Returns all the environment variables that are specific to Tuist (prefixed with TUIST_)
    public var tuistVariables: [String: String] {
        ProcessInfo.processInfo.environment.filter { $0.key.hasPrefix("TUIST_") }
    }

    public var manifestLoadingVariables: [String: String] {
        let allowedVariableKeys = [
            "DEVELOPER_DIR",
        ]
        let allowedVariables = ProcessInfo.processInfo.environment.filter {
            allowedVariableKeys.contains($0.key)
        }
        return tuistVariables.merging(allowedVariables, uniquingKeysWith: { $1 })
    }

    public var workspacePath: AbsolutePath? {
        if let pathString = ProcessInfo.processInfo.environment["WORKSPACE_PATH"] {
            return try? AbsolutePath(validating: pathString)
        } else {
            return nil
        }
    }

    public var schemeName: String? {
        ProcessInfo.processInfo.environment["SCHEME_NAME"]
    }

    public func currentExecutablePath() -> AbsolutePath? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        var pathLength = UInt32(buffer.count)
        if _NSGetExecutablePath(&buffer, &pathLength) == 0 {
            // swiftlint:disable:next force_try
            return try? AbsolutePath(validating: String(cString: buffer))
        } else {
            return nil
        }
    }
}

#if DEBUG
    extension ServiceContext {
        public var testEnvironment: MockEnvironment? {
            return environment as? MockEnvironment
        }
    }

    public final class MockEnvironment: Environmenting {
        fileprivate let directory: TemporaryDirectory
        fileprivate var setupCallCount: UInt = 0
        fileprivate var setupErrorStub: Error?

        public init() throws {
            directory = try TemporaryDirectory(removeTreeOnDeinit: true)
        }

        public var isVerbose: Bool = false
        public var queueDirectoryStub: AbsolutePath?
        public var shouldOutputBeColoured: Bool = false
        public var isStandardOutputInteractive: Bool = false
        public var tuistVariables: [String: String] = [:]
        public var manifestLoadingVariables: [String: String] = [:]
        public var isStatsEnabled: Bool = true
        public var isGitHubActions: Bool = false

        public var automationPath: AbsolutePath? {
            nil
        }

        public var cacheDirectory: AbsolutePath {
            directory.path.appending(components: ".cache")
        }

        public var stateDirectory: AbsolutePath {
            directory.path.appending(component: "state")
        }

        public var queueDirectory: AbsolutePath {
            queueDirectoryStub ?? directory.path.appending(component: Constants.AsyncQueue.directoryName)
        }

        public var workspacePath: AbsolutePath? { nil }
        public var schemeName: String? { nil }
        public var currentExecutablePathStub: AbsolutePath?
        public func currentExecutablePath() -> AbsolutePath? { currentExecutablePathStub }
    }
#endif
