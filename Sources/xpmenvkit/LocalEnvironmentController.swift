import Basic
import Foundation

protocol LocalEnvironmentControlling: AnyObject {
    var versionsDirectory: AbsolutePath { get }
    func setup() throws
}

class LocalEnvironmentController: LocalEnvironmentControlling {
    /// Returns the default local directory.
    static let defaultDirectory: AbsolutePath = AbsolutePath(URL(fileURLWithPath: NSHomeDirectory()).path).appending(component: ".xpm")

    // MARK: - Attributes

    /// Directory.
    private let directory: AbsolutePath

    /// Filemanager.
    private let fileManager: FileManager = .default

    init(directory: AbsolutePath = LocalEnvironmentController.defaultDirectory) {
        self.directory = directory
    }

    // MARK: - LocalEnvironmentControlling

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
}
