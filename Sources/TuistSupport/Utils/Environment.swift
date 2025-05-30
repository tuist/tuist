import Darwin
import FileSystem
import Foundation
import Mockable
import Path

/// Protocol that defines the interface of a local environment controller.
/// It manages the local directory where tuistenv stores the tuist versions and user settings.
@Mockable
public protocol Environmenting: Sendable {
    /// It returns an ID that uniquely identifies the process.
    var processId: String { get }

    /// Returns true if the output of Tuist should be coloured.
    var shouldOutputBeColoured: Bool { get }

    /// Returns the environment variables.
    var variables: [String: String] { get }

    /// Returns the arguments that have been passed to the process.
    var arguments: [String] { get }

    /// Returns all the environment variables that can be included during the manifest loading process
    var manifestLoadingVariables: [String: String] { get }

    /// Returns true if Tuist is running with verbose mode enabled.
    var isVerbose: Bool { get }

    /// Returns the path to the cache directory. Configurable via the `XDG_CACHE_HOME` environment variable
    var cacheDirectory: AbsolutePath { get }

    /// Returns the path to the state directory. Configurable via the `XDG_STATE_HOME` environment variable
    var stateDirectory: AbsolutePath { get }

    /// Returns the path to the config directory. Configurable via the `XDG_CONFIG_HOME` environment variable
    var configDirectory: AbsolutePath { get }

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

private let truthyValues = ["1", "true", "TRUE", "yes", "YES"]

extension Environmenting {
    public var tuistVariables: [String: String] {
        variables.filter { $0.key.hasPrefix("TUIST_") }
    }

    public func isVariableTruthy(_ name: String) -> Bool {
        guard let value = variables[name] else { return false }
        return truthyValues.contains(value)
    }

    public var isCI: Bool {
        let ciPlatformVariables = [
            // GitHub: https://help.github.com/en/actions/automating-your-workflow-with-github-actions/using-environment-variables
            "GITHUB_RUN_ID",
            // CircleCI: https://circleci.com/docs/2.0/env-vars/
            // Bitrise: https://devcenter.bitrise.io/builds/available-environment-variables/
            // Buildkite: https://buildkite.com/docs/pipelines/environment-variables
            // Travis: https://docs.travis-ci.com/user/environment-variables/
            "CI",
            // Jenkins: https://wiki.jenkins.io/display/JENKINS/Building+a+software+project
            "BUILD_NUMBER",
        ]
        return variables.first(where: {
            ciPlatformVariables.contains($0.key)
        }) != nil
    }
}

/// Local environment controller.
public struct Environment: Environmenting {
    @TaskLocal public static var current: Environmenting = Environment()
    public var processId = UUID().uuidString

    // MARK: - Attributes

    /// File handler instance.
    public var variables: [String: String] { ProcessInfo.processInfo.environment }
    public var arguments: [String] { ProcessInfo.processInfo.arguments }

    /// Returns true if the output of Tuist should be coloured.
    public var shouldOutputBeColoured: Bool {
        let noColor =
            if let noColorEnvVariable = variables["NO_COLOR"] {
                truthyValues.contains(noColorEnvVariable)
            } else {
                false
            }
        let ciColorForce =
            if let ciColorForceEnvVariable = variables["CLICOLOR_FORCE"] {
                truthyValues.contains(ciColorForceEnvVariable)
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
        if let githubActions = variables["GITHUB_ACTIONS"] {
            return truthyValues.contains(githubActions)
        } else {
            return false
        }
    }

    /// Returns true if the standard output is interactive.
    public var isStandardOutputInteractive: Bool {
        let termType = variables["TERM"]
        if let t = termType, t.lowercased() != "dumb", isatty(fileno(stdout)) != 0 {
            return true
        }
        return false
    }

    public var isVerbose: Bool {
        guard let variable = variables[
            "TUIST_CONFIG_VERBOSE"
        ]
        else { return false }
        return truthyValues.contains(variable)
    }

    public var isStatsEnabled: Bool {
        guard let variable = variables[
            "TUIST_CONFIG_STATS_OPT_OUT"
        ]
        else { return true }
        let userOptedOut = truthyValues.contains(variable)
        return !userOptedOut
    }

    public var cacheDirectory: AbsolutePath {
        let baseCacheDirectory: AbsolutePath
        if let cacheDirectoryPathString = variables["XDG_CACHE_HOME"],
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
        if let stateDirectoryPathString = variables["XDG_STATE_HOME"],
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

    public var configDirectory: AbsolutePath {
        let baseConfigDirectory: AbsolutePath
        if let configDirectoryPathString = variables["XDG_CONFIG_HOME"],
           let configDirectory = try? AbsolutePath(validating: configDirectoryPathString)
        {
            baseConfigDirectory = configDirectory
        } else {
            // swiftlint:disable:next force_try
            let homeDirectory = try! Path.AbsolutePath(validating: NSHomeDirectory())
            baseConfigDirectory = homeDirectory.appending(components: [".config"])
        }

        return baseConfigDirectory.appending(component: "tuist")
    }

    public var queueDirectory: AbsolutePath {
        if let envVariable = variables[
            "TUIST_CONFIG_QUEUE_DIRECTORY"
        ] {
            return try! AbsolutePath(validating: envVariable) // swiftlint:disable:this force_try
        } else {
            return cacheDirectory.appending(component: "Queue")
        }
    }

    public var manifestLoadingVariables: [String: String] {
        let allowedVariableKeys = [
            "DEVELOPER_DIR",
        ]
        let allowedVariables = variables.filter {
            allowedVariableKeys.contains($0.key)
        }
        return tuistVariables.merging(allowedVariables, uniquingKeysWith: { $1 })
    }

    public var workspacePath: AbsolutePath? {
        if let pathString = variables["WORKSPACE_PATH"] {
            return try? AbsolutePath(validating: pathString)
        } else {
            return nil
        }
    }

    public var schemeName: String? {
        variables["SCHEME_NAME"]
    }

    public func currentExecutablePath() -> AbsolutePath? {
        Self.currentExecutablePath()
    }

    public static func currentExecutablePath() -> AbsolutePath? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        var pathLength = UInt32(buffer.count)
        if _NSGetExecutablePath(&buffer, &pathLength) == 0 {
            let pathString = String(cString: buffer)
            // When we run acceptance tests, where the CLI doesn't get compiled,
            // this path returns the path to xctest:
            // - /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Xcode/Agents/xctest
            // In those cases we want to return nil and let the caller manage that scenario.
            if pathString.hasSuffix("xctest") {
                return nil
            } else {
                return try? AbsolutePath(validating: pathString)
            }
        } else {
            return nil
        }
    }
}
