import Foundation

protocol LocalEnvironmentControlling: AnyObject {
    var versionsDirectory: URL { get }
    func setup() throws
}

class LocalEnvironmentController: LocalEnvironmentControlling {
    /// Returns the default local directory.
    static let defaultDirectory: URL = URL(fileURLWithPath: "/usr/local/xpm")

    // MARK: - Attributes

    /// Directory.
    private let directory: URL

    /// Filemanager.
    private let fileManager: FileManager = .default

    init(directory: URL = LocalEnvironmentController.defaultDirectory) {
        self.directory = directory
    }

    // MARK: - LocalEnvironmentControlling

    func setup() throws {
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(atPath: directory.path, withIntermediateDirectories: true, attributes: nil)
        }
        if !fileManager.fileExists(atPath: versionsDirectory.path) {
            try fileManager.createDirectory(atPath: versionsDirectory.path, withIntermediateDirectories: true, attributes: nil)
        }
    }

    /// Returns the directory where all the versions are.
    var versionsDirectory: URL {
        return directory.appendingPathComponent("Versions")
    }
}
