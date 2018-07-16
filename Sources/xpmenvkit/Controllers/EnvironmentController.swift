import Basic
import Foundation

/// Protocol that defines the interface of a local environment controller.
/// It manages the local directory where xpmenv stores the xpm versions and user settings.
protocol EnvironmentControlling: AnyObject {
    /// Returns the versions directory.
    var versionsDirectory: AbsolutePath { get }

    /// Returns the path of a given version.
    /// Note: The path is always returned regardless of the version existing or not.
    ///
    /// - Parameter version: version reference.
    /// - Returns: the path to the given version.
    func path(version: String) -> AbsolutePath

    /// Returns the path to the settings.
    var settingsPath: AbsolutePath { get }

    /// Sets up the local environment.
    ///
    /// - Throws: an error if something the directories creation fails.
    func setup() throws
}

/// Local environment controller.
class EnvironmentController: EnvironmentControlling {
    /// Returns the default local directory.
    static let defaultDirectory: AbsolutePath = AbsolutePath(URL(fileURLWithPath: NSHomeDirectory()).path).appending(component: ".xpm")

    // MARK: - Attributes

    /// Directory.
    private let directory: AbsolutePath

    /// Filemanager.
    private let fileManager: FileManager = .default

    init(directory: AbsolutePath = EnvironmentController.defaultDirectory) {
        self.directory = directory
    }

    // MARK: - EnvironmentControlling

    /// Sets up the local environment.
    ///
    /// - Throws: an error if something the directories creation fails.
    func setup() throws {
        if !fileManager.fileExists(atPath: directory.asString) {
            try fileManager.createDirectory(atPath: directory.asString, withIntermediateDirectories: true, attributes: nil)
        }
        if !fileManager.fileExists(atPath: versionsDirectory.asString) {
            try fileManager.createDirectory(atPath: versionsDirectory.asString, withIntermediateDirectories: true, attributes: nil)
        }
    }

    /// Returns the directory where all the versions are.
    var versionsDirectory: AbsolutePath {
        return directory.appending(component: "Versions")
    }

    /// Returns the path of a given version.
    /// Note: The path is always returned regardless of the version existing or not.
    ///
    /// - Parameter version: version reference.
    /// - Returns: the path to the given version.
    func path(version: String) -> AbsolutePath {
        return versionsDirectory.appending(component: version)
    }

    /// Settings path.
    var settingsPath: AbsolutePath {
        return directory.appending(component: "settings.json")
    }
}
