import Foundation
import TSCBasic
import TuistSupport

/// Protocol that defines the interface of an instance that can install versions of TuistEnv.
protocol EnvInstalling: AnyObject {
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
enum EnvInstallerError: FatalError, Equatable {
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
final class EnvInstaller: EnvInstalling {
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
            bundleURL: URL(string: "https://github.com/tuist/tuist/releases/download/\(version)/tuistenv.zip")!,
            version: version,
            temporaryDirectory: temporaryDirectory
        )
    }

    func installFromBundle(
        bundleURL: URL,
        version: String,
        temporaryDirectory: AbsolutePath
    ) throws {
        let installationPath = try System.shared.which("tuist")

        // Download bundle
        logger.notice("Downloading TuistEnv version \(version)")
        let downloadPath = temporaryDirectory.appending(component: Constants.envBundleName)
        try System.shared.run(["/usr/bin/curl", "-LSs", "--output", downloadPath.pathString, bundleURL.absoluteString])

        // Unzip
        logger.notice("Installing…")
        try System.shared.run(["/usr/bin/unzip", "-q", downloadPath.pathString, "tuistenv", "-d", temporaryDirectory.pathString])

        // Copy
        let cpArgs = ["cp", temporaryDirectory.appending(component: "tuistenv").pathString, installationPath]
        do {
            try System.shared.run(cpArgs)
        } catch {
            try System.shared.run(["sudo"] + cpArgs)
        }

        logger.notice("TuistEnv Version \(version) installed")
    }
}
