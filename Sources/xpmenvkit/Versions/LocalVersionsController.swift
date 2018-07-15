import Basic
import Foundation
import Utility
import xpmcore

protocol LocalVersionsControlling: AnyObject {
    func versions() -> [Version]
}

enum LocalVersionsControllerError: FatalError {
    case existingVersion(Version)

    var type: ErrorType {
        switch self {
        case .existingVersion: return .abort
        }
    }

    var description: String {
        switch self {
        case let .existingVersion(version):
            return "The version \(version.description) is already installed."
        }
    }
}

class LocalVersionsController: LocalVersionsControlling {
    /// Environment controller.
    let environmentController: EnvironmentControlling

    /// File manager.
    let fileManager: FileManager = .default

    init(environmentController: EnvironmentControlling) {
        self.environmentController = environmentController
    }

    /// Returns the list of all the available versions.
    ///
    /// - Returns: list with all the available veresions.
    func versions() -> [Version] {
        let paths = fileManager.subpaths(atPath: environmentController.versionsDirectory.asString) ?? []
        return paths
            .compactMap({ URL(fileURLWithPath: $0).lastPathComponent })
            .compactMap(Version.init)
    }

    /// Returns the path where a given version is installed.
    ///
    /// - Parameter version: version whose local path will be returned.
    /// - Returns: path to the folder where the version is installed.
    func path(version: Version) -> AbsolutePath? {
        let path = environmentController.versionsDirectory.appending(component: version.description)
        if fileManager.fileExists(atPath: path.asString) {
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
    func install(version: Version, install: (AbsolutePath) -> Void) throws {
        let existingVersions = versions()
        if existingVersions.contains(version) {
            throw LocalVersionsControllerError.existingVersion(version)
        }
        let path = environmentController.versionsDirectory.appending(component: version.description)
        try fileManager.createDirectory(at: URL(fileURLWithPath: path.asString), withIntermediateDirectories: true, attributes: nil)
        install(path)

        // We remove the directory if nothing has been installed
        if fileManager.subpaths(atPath: path.asString)?.count == 0 {
            try fileManager.removeItem(at: URL(fileURLWithPath: path.asString))
        }
    }
}
