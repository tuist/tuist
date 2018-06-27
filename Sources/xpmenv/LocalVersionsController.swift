import Foundation

protocol LocalVersionsControlling: AnyObject {
    func versions() -> [Version]
}

enum LocalVersionsControllerError: FatalError {
    case existingVersion(Version)

    var errorDescription: String {
        switch self {
        case let .existingVersion(version):
            return "The version \(version.description) is already installed."
        }
    }
}

class LocalVersionsController: LocalVersionsControlling {
    /// Environment controller.
    let environmentController: LocalEnvironmentControlling

    /// File manager.
    let fileManager: FileManager = .default

    init(environmentController: LocalEnvironmentControlling) {
        self.environmentController = environmentController
    }

    /// Returns the list of all the available versions.
    ///
    /// - Returns: list with all the available veresions.
    func versions() -> [Version] {
        let paths = fileManager.subpaths(atPath: environmentController.versionsDirectory.path) ?? []
        return paths
            .compactMap({ URL(fileURLWithPath: $0).lastPathComponent })
            .compactMap(Version.init)
    }

    /// Returns the path where a given version is installed.
    ///
    /// - Parameter version: version whose local path will be returned.
    /// - Returns: path to the folder where the version is installed.
    func path(version: Version) -> URL? {
        let path = environmentController.versionsDirectory.appendingPathComponent(version.description)
        if fileManager.fileExists(atPath: path.path) {
            return path
        }
        return nil
    }

    /// It creates an installation directory for the given version and calls
    /// the closure passing the path where all the files should be installed into.
    ///
    /// - Parameters:
    ///   - version: version to be installed.
    ///   - install: closure that contains the installation steps.
    /// - Throws: an error if the version already exists.
    func install(version: Version, install: (URL) -> Void) throws {
        let existingVersions = versions()
        if existingVersions.contains(version) {
            throw LocalVersionsControllerError.existingVersion(version)
        }
        let path = environmentController.versionsDirectory.appendingPathComponent(version.description)
        try fileManager.createDirectory(at: path, withIntermediateDirectories: true, attributes: nil)
        install(path)

        // We remove the directory if nothing has been installed
        if fileManager.subpaths(atPath: path.path)?.count == 0 {
            try fileManager.removeItem(at: path)
        }
    }
}
