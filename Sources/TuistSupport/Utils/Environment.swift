import Darwin.C
import Foundation
import TSCBasic

/// Protocol that defines the interface of a local environment controller.
/// It manages the local directory where tuistenv stores the tuist versions and user settings.
public protocol Environmenting: AnyObject {
    /// Returns the versions directory.
    var versionsDirectory: AbsolutePath { get }

    /// Returns the path to the settings.
    var settingsPath: AbsolutePath { get }

    /// Returns true if the output of Tuist should be coloured.
    var shouldOutputBeColoured: Bool { get }

    /// Returns automation path
    /// Only to be used for acceptance tests
    var automationPath: AbsolutePath? { get }

    /// Returns all the environment variables that are specific to Tuist (prefixed with TUIST_)
    var tuistVariables: [String: String] { get }

    /// Returns all the environment variables that are specific to Tuist configuration (prefixed with TUIST_CONFIG_)
    var tuistConfigVariables: [String: String] { get }

    /// Returns all the environment variables that can be included during the manifest loading process
    var manifestLoadingVariables: [String: String] { get }

    /// Returns true if Tuist is running with verbose mode enabled.
    var isVerbose: Bool { get }

    /// Returns the path to the directory where the async queue events are persisted.
    var queueDirectory: AbsolutePath { get }

    /// Returns true unless the user specifically opted out from stats
    var isStatsEnabled: Bool { get }

    /// Sets up the local environment.
    func bootstrap() throws
}

/// Local environment controller.
public class Environment: Environmenting {
    public static var shared: Environmenting = Environment()

    /// Returns the default local directory.
    static let defaultDirectory = try! AbsolutePath( // swiftlint:disable:this force_try
        validating: URL(fileURLWithPath: NSHomeDirectory()).path
    ).appending(component: ".tuist")

    // MARK: - Attributes

    /// Directory.
    private let directory: AbsolutePath

    /// File handler instance.
    private let fileHandler: FileHandling

    /// Default public constructor.
    convenience init() {
        self.init(
            directory: Environment.defaultDirectory,
            fileHandler: FileHandler.shared
        )
    }

    /// Default environment constructor.
    ///
    /// - Parameters:
    ///   - directory: Directory where the Tuist environment files will be stored.
    ///   - fileHandler: File handler instance to perform file operations.
    init(directory: AbsolutePath, fileHandler: FileHandling) {
        self.directory = directory
        self.fileHandler = fileHandler
    }

    // MARK: - EnvironmentControlling

    /// Sets up the local environment.
    public func bootstrap() throws {
        try [directory, versionsDirectory].forEach {
            if !fileHandler.exists($0) {
                try fileHandler.createFolder($0)
            }
        }
    }

    /// Returns true if the output of Tuist should be coloured.
    public var shouldOutputBeColoured: Bool {
        if let coloredOutput = ProcessInfo.processInfo.environment[Constants.EnvironmentVariables.colouredOutput] {
            return Constants.trueValues.contains(coloredOutput)
        } else {
            return isStandardOutputInteractive
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
        guard let variable = ProcessInfo.processInfo.environment[Constants.EnvironmentVariables.verbose] else { return false }
        return Constants.trueValues.contains(variable)
    }

    public var isStatsEnabled: Bool {
        guard let variable = ProcessInfo.processInfo.environment[Constants.EnvironmentVariables.statsOptOut] else { return true }
        let userOptedOut = Constants.trueValues.contains(variable)
        return !userOptedOut
    }

    /// Returns the directory where all the versions are.
    public var versionsDirectory: AbsolutePath {
        if let envVariable = ProcessInfo.processInfo.environment[Constants.EnvironmentVariables.versionsDirectory] {
            return try! AbsolutePath(validating: envVariable) // swiftlint:disable:this force_try
        } else {
            return directory.appending(component: "Versions")
        }
    }

    public var automationPath: AbsolutePath? {
        ProcessInfo.processInfo.environment[Constants.EnvironmentVariables.automationPath]
            .map { try! AbsolutePath(validating: $0) } // swiftlint:disable:this force_try
    }

    public var queueDirectory: AbsolutePath {
        if let envVariable = ProcessInfo.processInfo.environment[Constants.EnvironmentVariables.queueDirectory] {
            return try! AbsolutePath(validating: envVariable) // swiftlint:disable:this force_try
        } else {
            return directory.appending(component: Constants.AsyncQueue.directoryName)
        }
    }

    /// Returns all the environment variables that are specific to Tuist (prefixed with TUIST_)
    public var tuistVariables: [String: String] {
        ProcessInfo.processInfo.environment.filter { $0.key.hasPrefix("TUIST_") }.filter { !$0.key.hasPrefix("TUIST_CONFIG_") }
    }

    /// Returns all the environment variables that are specific to Tuist config (prefixed with TUIST_CONFIG_)
    public var tuistConfigVariables: [String: String] {
        ProcessInfo.processInfo.environment.filter { $0.key.hasPrefix("TUIST_CONFIG_") }
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

    /// Settings path.
    public var settingsPath: AbsolutePath {
        directory.appending(component: "settings.json")
    }
}
