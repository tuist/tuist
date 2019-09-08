import Basic
import Foundation

/// Protocol that defines the interface of a local environment controller.
/// It manages the local directory where tuistenv stores the tuist versions and user settings.
public protocol Environmenting: AnyObject {
    /// Returns the versions directory.
    var versionsDirectory: AbsolutePath { get }

    /// Returns the path to the settings.
    var settingsPath: AbsolutePath { get }

    /// Returns the directory where all the derived projects are generated.
    var derivedProjectsDirectory: AbsolutePath { get }
    
    /// Returns true if the output of Tuist should be coloured.
    var shouldOutputBeColoured: Bool { get }
}

/// Local environment controller.
public class Environment: Environmenting {
    public static var shared: Environmenting = Environment()

    /// Returns the default local directory.
    static let defaultDirectory: AbsolutePath = AbsolutePath(URL(fileURLWithPath: NSHomeDirectory()).path).appending(component: ".tuist")

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
        [directory, versionsDirectory, derivedProjectsDirectory].forEach {
            if !fileHandler.exists($0) {
                // swiftlint:disable:next force_try
                try! fileHandler.createFolder($0)
            }
        }
    }

    /// Returns true if the output of Tuist should be coloured.
    public var shouldOutputBeColoured: Bool {
        let enabledValues = ["1", "true", "TRUE", "yes", "YES"]
        guard let colouredValue = ProcessInfo.processInfo.environment.first(where: { $0.key == Constants.EnvironmentVariables.colouredOutput })?.value else {
            return false
        }
        let ciValue = ProcessInfo.processInfo.environment.first(where: { $0.key == "CI" })?.value ?? "0"

        let isCI = enabledValues.contains(ciValue)
        let isEnabled = enabledValues.contains(colouredValue)

        return isEnabled && !isCI
    }

    /// Returns the directory where all the versions are.
    public var versionsDirectory: AbsolutePath {
        return directory.appending(component: "Versions")
    }

    /// Returns the directory where all the derived projects are generated.
    public var derivedProjectsDirectory: AbsolutePath {
        return directory.appending(component: "DerivedProjects")
    }

    /// Settings path.
    public var settingsPath: AbsolutePath {
        return directory.appending(component: "settings.json")
    }
}
