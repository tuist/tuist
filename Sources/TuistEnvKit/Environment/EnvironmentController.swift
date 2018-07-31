import Basic
import Foundation

/// Protocol that defines the interface of a local environment controller.
/// It manages the local directory where tuistenv stores the tuist versions and user settings.
protocol EnvironmentControlling: AnyObject {
    /// Returns the versions directory.
    var versionsDirectory: AbsolutePath { get }

    /// Returns the path to the settings.
    var settingsPath: AbsolutePath { get }
}

/// Local environment controller.
class EnvironmentController: EnvironmentControlling {
    /// Returns the default local directory.
    static let defaultDirectory: AbsolutePath = AbsolutePath(URL(fileURLWithPath: NSHomeDirectory()).path).appending(component: ".tuist")

    // MARK: - Attributes

    /// Directory.
    private let directory: AbsolutePath

    /// Filemanager.
    
    private let fileManager: FileManager = .default

    init(directory: AbsolutePath = EnvironmentController.defaultDirectory) {
        self.directory = directory
        setup()
    }

    // MARK: - EnvironmentControlling

    /// Sets up the local environment.
    ///
    /// - Throws: an error if something the directories creation fails.
    private func setup() {
        // Note: It should be safe to use try! here
        if !fileManager.fileExists(atPath: directory.asString) {
            try! fileManager.createDirectory(atPath: directory.asString, withIntermediateDirectories: true, attributes: nil)
        }
        if !fileManager.fileExists(atPath: versionsDirectory.asString) {
            try! fileManager.createDirectory(atPath: versionsDirectory.asString, withIntermediateDirectories: true, attributes: nil)
        }
    }

    /// Returns the directory where all the versions are.
    var versionsDirectory: AbsolutePath {
        return directory.appending(component: "Versions")
    }

    /// Settings path.
    var settingsPath: AbsolutePath {
        return directory.appending(component: "settings.json")
    }
}
