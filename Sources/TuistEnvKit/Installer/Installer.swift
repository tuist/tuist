import Foundation
import RxBlocking
import TSCBasic
import TuistSupport

/// Protocol that defines the interface of an instance that can install versions of Tuist.
protocol Installing: AnyObject {
    /// It installs a version of Tuist in the local environment.
    ///
    /// - Parameters:
    ///   - version: Version to be installed.
    ///   - force: When true, it ignores the Swift version and compiles it from the source.
    /// - Throws: An error if the installation fails.
    func install(version: String, force: Bool) throws
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

    static func == (lhs: InstallerError, rhs: InstallerError) -> Bool {
        switch (lhs, rhs) {
        case let (.versionNotFound(lhsVersion), .versionNotFound(rhsVersion)):
            return lhsVersion == rhsVersion
        case let (.incompatibleSwiftVersion(lhsLocal, lhsExpected), .incompatibleSwiftVersion(rhsLocal, rhsExpected)):
            return lhsLocal == rhsLocal && lhsExpected == rhsExpected
        default:
            return false
        }
    }
}

/// Class that manages the installation of Tuist versions.
final class Installer: Installing {
    // MARK: - Attributes

    let buildCopier: BuildCopying
    let versionsController: VersionsControlling
    let googleCloudStorageClient: GoogleCloudStorageClienting

    // MARK: - Init

    init(buildCopier: BuildCopying = BuildCopier(),
         versionsController: VersionsControlling = VersionsController(),
         googleCloudStorageClient: GoogleCloudStorageClienting = GoogleCloudStorageClient())
    {
        self.buildCopier = buildCopier
        self.versionsController = versionsController
        self.googleCloudStorageClient = googleCloudStorageClient
    }

    // MARK: - Installing

    func install(version: String, force: Bool) throws {
        try withTemporaryDirectory { temporaryDirectory in
            try install(version: version, temporaryDirectory: temporaryDirectory, force: force)
        }
    }

    func install(version: String, temporaryDirectory: AbsolutePath, force: Bool = false) throws {
        // We ignore the Swift version and install from the soruce code
        if force {
            logger.notice("Forcing the installation of \(version) from the source code")
            try installFromSource(version: version,
                                  temporaryDirectory: temporaryDirectory)
            return
        }

        let bundleURL: URL? = try googleCloudStorageClient.tuistBundleURL(version: version).toBlocking().first() ?? nil

        if let bundleURL = bundleURL {
            try installFromBundle(bundleURL: bundleURL,
                                  version: version,
                                  temporaryDirectory: temporaryDirectory)
        } else {
            try installFromSource(version: version,
                                  temporaryDirectory: temporaryDirectory)
        }
    }

    func installFromBundle(bundleURL: URL,
                           version: String,
                           temporaryDirectory: AbsolutePath) throws
    {
        try versionsController.install(version: version, installation: { installationDirectory in

            // Download bundle
            logger.notice("Downloading version \(version)")

            let downloadPath = temporaryDirectory.appending(component: Constants.bundleName)
            try System.shared.run("/usr/bin/curl", "-LSs", "--output", downloadPath.pathString, bundleURL.absoluteString)

            // Unzip
            logger.notice("Installing...")
            try System.shared.run("/usr/bin/unzip", "-q", downloadPath.pathString, "-d", installationDirectory.pathString)

            try createTuistVersionFile(version: version, path: installationDirectory)
            logger.notice("Version \(version) installed")
        })
    }

    // swiftlint:disable:next function_body_length
    func installFromSource(version: String,
                           temporaryDirectory: AbsolutePath) throws
    {
        try versionsController.install(version: version) { installationDirectory in
            // Paths
            let buildDirectory = temporaryDirectory.appending(RelativePath(".build/release/"))

            // Cloning and building
            logger.notice("Pulling source code")
            _ = try System.shared.observable(["/usr/bin/env", "git", "clone", Constants.gitRepositoryURL, temporaryDirectory.pathString])
                .mapToString()
                .printStandardError()
                .toBlocking()
                .last()

            let gitCheckoutResult = System.shared.observable(["/usr/bin/env", "git", "-C", temporaryDirectory.pathString, "checkout", version])
                .mapToString()
                .toBlocking()
                .materialize()

            if case let .failed(elements, error) = gitCheckoutResult {
                if elements.map({ $0.value }).first(where: { $0.contains("did not match any file(s) known to git") }) != nil {
                    throw InstallerError.versionNotFound(version)
                } else {
                    throw error
                }
            }

            logger.notice("Building using Swift (it might take a while)")
            let swiftPath = try System.shared
                .observable(["/usr/bin/xcrun", "-f", "swift"])
                .mapToString()
                .collectOutput()
                .toBlocking()
                .last()!
                .standardOutput
                .spm_chuzzle()!

            _ = try System.shared.observable([swiftPath, "build",
                                              "--product", "tuist",
                                              "--package-path", temporaryDirectory.pathString,
                                              "--configuration", "release"])
                .mapToString()
                .printStandardError()
                .toBlocking()
                .last()

            _ = try System.shared.observable([swiftPath, "build",
                                              "--product", "ProjectDescription",
                                              "--package-path", temporaryDirectory.pathString,
                                              "--configuration", "release",
                                              "-Xswiftc", "-enable-library-evolution",
                                              "-Xswiftc", "-emit-module-interface",
                                              "-Xswiftc", "-emit-module-interface-path",
                                              "-Xswiftc", temporaryDirectory.appending(RelativePath(".build/release/ProjectDescription.swiftinterface")).pathString]) // swiftlint:disable:this line_length
                .mapToString()
                .printStandardError()
                .toBlocking()
                .last()

            if FileHandler.shared.exists(installationDirectory) {
                try FileHandler.shared.delete(installationDirectory)
            }
            try FileHandler.shared.createFolder(installationDirectory)

            let templatesDirectory = temporaryDirectory.appending(component: Constants.templatesDirectoryName)
            if FileHandler.shared.exists(templatesDirectory) {
                try FileHandler.shared.copy(from: templatesDirectory,
                                            to: buildDirectory.appending(component: Constants.templatesDirectoryName))
            }

            try buildCopier.copy(from: buildDirectory,
                                 to: installationDirectory)

            try createTuistVersionFile(version: version, path: installationDirectory)
            logger.notice("Version \(version) installed")
        }
    }

    private func createTuistVersionFile(version: String, path: AbsolutePath) throws {
        let tuistVersionPath = path.appending(component: Constants.versionFileName)
        try "\(version)".write(to: tuistVersionPath.url,
                               atomically: true,
                               encoding: .utf8)
    }
}
