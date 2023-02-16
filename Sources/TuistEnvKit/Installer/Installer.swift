import Foundation
import TSCBasic
import TuistSupport

/// Protocol that defines the interface of an instance that can install versions of Tuist.
protocol Installing: AnyObject {
    /// It installs a version of Tuist in the local environment.
    ///
    /// - Parameters:
    ///   - version: Version to be installed.
    /// - Throws: An error if the installation fails.
    func install(version: String) throws
}

/// Error thrown by the installer.
///
/// - versionNotFound: When the specified version cannot be found.
/// - incompatibleSwiftVersion: When the environment Swift version is incompatible with the Swift version Tuist has been compiled with.
enum InstallerError: FatalError, Equatable {
    case versionNotFound(String)
    case incompatibleSwiftVersion(local: String, expected: String)

    var type: ErrorType {
        switch self {
        case .versionNotFound: return .abort
        case .incompatibleSwiftVersion: return .abort
        }
    }

    var description: String {
        switch self {
        case let .versionNotFound(version):
            return "Version \(version) not found"
        case let .incompatibleSwiftVersion(local, expected):
            return "Found \(local) Swift version but expected \(expected)"
        }
    }
}

/// Class that manages the installation of Tuist versions.
final class Installer: Installing {
    // MARK: - Attributes

    let buildCopier: BuildCopying
    let versionsController: VersionsControlling

    // MARK: - Init

    init(
        buildCopier: BuildCopying = BuildCopier(),
        versionsController: VersionsControlling = VersionsController()
    ) {
        self.buildCopier = buildCopier
        self.versionsController = versionsController
    }

    // MARK: - Installing

    func install(version: String) throws {
        try withTemporaryDirectory { temporaryDirectory in
            try install(version: version, temporaryDirectory: temporaryDirectory)
        }
    }

    func install(version: String, temporaryDirectory: AbsolutePath) throws {
        try installFromBundle(
            bundleURL: URL(string: "https://github.com/tuist/tuist/releases/download/\(version)/tuist.zip")!,
            version: version,
            temporaryDirectory: temporaryDirectory
        )
    }

    func installFromBundle(
        bundleURL: URL,
        version: String,
        temporaryDirectory: AbsolutePath
    ) throws {
        try versionsController.install(version: version, installation: { installationDirectory in

            // Download bundle
            logger.notice("Downloading version \(version)")

            let downloadPath = temporaryDirectory.appending(component: Constants.bundleName)
            try System.shared.run(["/usr/bin/curl", "-LSs", "--output", downloadPath.pathString, bundleURL.absoluteString])

            // Unzip
            logger.notice("Installing…")
            try System.shared.run(["/usr/bin/unzip", "-q", downloadPath.pathString, "-d", installationDirectory.pathString])

            logger.notice("Version \(version) installed")
        })
    }
}
