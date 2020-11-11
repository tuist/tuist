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

    /// Returns the cache directory
    var cacheDirectory: AbsolutePath { get }

    /// Returns the directory where the project description helper modules are cached.
    var projectDescriptionHelpersCacheDirectory: AbsolutePath { get }

    /// Returns the directory where the build artifacts are cached.
    var buildCacheDirectory: AbsolutePath { get }

    /// Returns all the environment variables that are specific to Tuist (prefixed with TUIST_)
    var tuistVariables: [String: String] { get }

    /// Returns all the environment variables that can be included during the manifest loading process
    var manifestLoadingVariables: [String: String] { get }

    /// Returns true if Tuist is running with verbose mode enabled.
    var isVerbose: Bool { get }

    /// Returns the path to the directory where the async queue events are persisted.
    var queueDirectory: AbsolutePath { get }
}

/// Local environment controller.
public class Environment: Environmenting {
    public static var shared: Environmenting = Environment()

    /// Returns the default local directory.
    static let defaultDirectory = AbsolutePath(URL(fileURLWithPath: NSHomeDirectory()).path).appending(component: ".tuist")

    // MARK: - Attributes

    /// Directory.
    private let directory: AbsolutePath

    /// File handler instance.
    private let fileHandler: FileHandling

    /// Default public constructor.
    convenience init() {
        self.init(directory: Environment.defaultDirectory,
                  fileHandler: FileHandler.shared)
    }

    /// Default environment constroller constructor.
    ///
    /// - Parameters:
    ///   - directory: Directory where the Tuist environment files will be stored.
    ///   - fileHandler: File handler instance to perform file operations.
    init(directory: AbsolutePath, fileHandler: FileHandling) {
        self.directory = directory
        self.fileHandler = fileHandler
        setup()
    }

    // MARK: - EnvironmentControlling

    /// Sets up the local environment.
    private func setup() {
        [directory, versionsDirectory, cacheDirectory].forEach {
            if !fileHandler.exists($0) {
                // swiftlint:disable:next force_try
                try! fileHandler.createFolder($0)
            }
        }
    }

    /// Returns true if the output of Tuist should be coloured.
    public var shouldOutputBeColoured: Bool {
        isStandardOutputInteractive || isColouredOutputEnvironmentTrue
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

    /// Returns the directory where all the versions are.
    public var versionsDirectory: AbsolutePath {
        if let envVariable = ProcessInfo.processInfo.environment[Constants.EnvironmentVariables.versionsDirectory] {
            return AbsolutePath(envVariable)
        } else {
            return directory.appending(component: "Versions")
        }
    }

    /// Returns the directory where the build artifacts are cached.
    public var buildCacheDirectory: AbsolutePath {
        cacheDirectory.appending(component: "BuildCache")
    }

    /// Returns the directory where the project description helper modules are cached.
    public var projectDescriptionHelpersCacheDirectory: AbsolutePath {
        cacheDirectory.appending(component: "ProjectDescriptionHelpers")
    }

    /// Returns the cache directory
    public var cacheDirectory: AbsolutePath {
        if let envVariable = ProcessInfo.processInfo.environment[Constants.EnvironmentVariables.cacheDirectory] {
            return AbsolutePath(envVariable)
        } else {
            return directory.appending(component: "Cache")
        }
    }

    public var queueDirectory: AbsolutePath {
        if let envVariable = ProcessInfo.processInfo.environment[Constants.EnvironmentVariables.queueDirectory] {
            return AbsolutePath(envVariable)
        } else {
            return directory.appending(component: Constants.AsyncQueue.directoryName)
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

    /// Settings path.
    public var settingsPath: AbsolutePath {
        directory.appending(component: "settings.json")
    }

    // MARK: - Fileprivate

    /// Return true if the the coloured output is forced through an environment variable.
    fileprivate var isColouredOutputEnvironmentTrue: Bool {
        let environment = ProcessInfo.processInfo.environment
        return !environment
            .filter { $0.key == Constants.EnvironmentVariables.colouredOutput }
            .filter { Constants.trueValues.contains($0.value) }
            .isEmpty
    }
}
