import Darwin
import FileSystem
import Foundation
import Path

/// Protocol that defines the interface of a local environment controller.
/// It manages the local directory where tuistenv stores the tuist versions and user settings.
public protocol Environmenting: AnyObject, Sendable {
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
    
    var workspacePath: AbsolutePath? { get }
}

/// Local environment controller.
public final class Environment: Environmenting {
    public static var shared: Environmenting {
        _shared.value
    }

    // swiftlint:disable:next identifier_name
    static let _shared: ThreadSafe<Environmenting> = ThreadSafe(Environment())

    // MARK: - Attributes

    /// File handler instance.
    private let fileHandler: FileHandling

    /// Default public constructor.
    convenience init() {
        self.init(
            fileHandler: FileHandler.shared
        )
    }

    /// Default environment constructor.
    ///
    /// - Parameters:
    ///   - fileHandler: File handler instance to perform file operations.
    init(fileHandler: FileHandling) {
        self.fileHandler = fileHandler
    }

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
}
