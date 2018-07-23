import Basic
import Foundation
import Utility
import TuistCore

protocol VersionsControlling: AnyObject {
    /// Installation
    typealias Installation = (AbsolutePath) throws -> Void

    /// This methods should be used for installing new versions of tuist.
    /// It calls the given installation closure with a directory where the
    /// app should be installed.
    ///
    /// - Parameters:
    ///   - version: version of the app that will be installed.
    ///   - installation: installation closure.
    func install(version: String, installation: Installation) throws

    /// Returns the path for given version.
    /// Note: The path is returned regardless of the version existing or not.
    ///
    /// - Parameter version: version whose path will be returned.
    /// - Returns: absolute path to the version.
    func path(version: String) -> AbsolutePath

    /// Returns a list with all the installed versions.
    ///
    /// - Returns: installed versions.
    func versions() -> [InstalledVersion]

    /// Returns the list of the semver versions.
    ///
    /// - Returns: semver versions.
    func semverVersions() -> [Version]
}

/// It represents an installed version that can be identified
/// by either the semver version, or the git reference.
///
/// - semver: semver-versioned version.
/// - reference: git-referenced version.
enum InstalledVersion: CustomStringConvertible, Equatable {
    case semver(Version)
    case reference(String)

    /// Version string value.
    var description: String {
        switch self {
        case let .reference(value): return value
        case let .semver(value): return value.description
        }
    }

    /// Compares two instances of InstalledVersion.
    ///
    /// - Parameters:
    ///   - lhs: first instance to be compared.
    ///   - rhs: second instance to be compared.
    /// - Returns: true if the two instances are equal.
    static func == (lhs: InstalledVersion, rhs: InstalledVersion) -> Bool {
        switch (lhs, rhs) {
        case let (.semver(lhsVersion), .semver(rhsVersion)):
            return lhsVersion == rhsVersion
        case let (.reference(lhsRef), .reference(rhsRef)):
            return lhsRef == rhsRef
        default:
            return false
        }
    }
}

class VersionsController: VersionsControlling {
    /// Environment controller.
    let environmentController: EnvironmentControlling

    /// File handler.
    let fileHandler: FileHandling

    /// Initializes the controller with its attributes.
    ///
    /// - Parameters:
    ///   - environmentController: environment controller.
    ///   - fileHandler: file handler.
    init(environmentController: EnvironmentControlling = EnvironmentController(),
         fileHandler: FileHandling = FileHandler()) {
        self.environmentController = environmentController
        self.fileHandler = fileHandler
    }

    /// This methods should be used for installing new versions of tuist.
    /// It calls the given installation closure with a directory where the
    /// app should be installed.
    ///
    /// - Parameters:
    ///   - version: version of the app that will be installed.
    ///   - installation: installation closure.
    func install(version: String, installation: Installation) throws {
        let tmpDir = try TemporaryDirectory(removeTreeOnDeinit: true)

        try installation(tmpDir.path)

        // Copy only if there's file in the folder
        if tmpDir.path.glob("*").count != 0 {
            let dstPath = path(version: version)
            if fileHandler.exists(dstPath) {
                try fileHandler.delete(dstPath)
            }
            try fileHandler.copy(from: tmpDir.path, to: dstPath)
        }
    }

    /// Returns the path for given version.
    /// Note: The path is returned regardless of the version existing or not.
    ///
    /// - Parameter version: version whose path will be returned.
    /// - Returns: absolute path to the version.
    func path(version: String) -> AbsolutePath {
        return environmentController.versionsDirectory.appending(component: version)
    }

    /// Returns a list with all the installed versions.
    ///
    /// - Returns: installed versions.
    func versions() -> [InstalledVersion] {
        return environmentController.versionsDirectory.glob("*").map { path in
            let versionStringValue = path.components.last!
            if let version = Version(string: versionStringValue) {
                return InstalledVersion.semver(version)
            } else {
                return InstalledVersion.reference(versionStringValue)
            }
        }
    }

    /// Returns the list of the semver versions.
    ///
    /// - Returns: semver versions.
    func semverVersions() -> [Version] {
        return versions().compactMap { version in
            if case let InstalledVersion.semver(semver) = version {
                return semver
            }
            return nil
        }
    }
}
