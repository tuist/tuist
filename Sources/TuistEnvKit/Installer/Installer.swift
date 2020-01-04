import Basic
import Foundation
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
    let githubClient: GitHubClienting

    // MARK: - Init

    init(buildCopier: BuildCopying = BuildCopier(),
         versionsController: VersionsControlling = VersionsController(),
         githubClient: GitHubClienting = GitHubClient()) {
        self.buildCopier = buildCopier
        self.versionsController = versionsController
        self.githubClient = githubClient
    }

    // MARK: - Installing

    func install(version: String, force: Bool) throws {
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        try install(version: version, temporaryDirectory: temporaryDirectory, force: force)
    }

    func install(version: String, temporaryDirectory: TemporaryDirectory, force: Bool = false) throws {
        // We ignore the Swift version and install from the soruce code
        if force {
            Printer.shared.print("Forcing the installation of \(version) from the source code")
            try installFromSource(version: version,
                                  temporaryDirectory: temporaryDirectory)
            return
        }

        var bundleURL: URL?
        do {
            bundleURL = try self.bundleURL(version: version)
        } catch {}

        if let bundleURL = bundleURL {
            try installFromBundle(bundleURL: bundleURL,
                                  version: version,
                                  temporaryDirectory: temporaryDirectory)
        } else {
            try installFromSource(version: version,
                                  temporaryDirectory: temporaryDirectory)
        }
    }

    func bundleURL(version: String) throws -> URL? {
        guard let release = try? githubClient.release(tag: version) else {
            Printer.shared.print(warning: "The release \(version) couldn't be obtained from GitHub")
            return nil
        }
        guard let bundleAsset = release.assets.first(where: { $0.name == Constants.bundleName }) else {
            Printer.shared.print(warning: "The release \(version) is not bundled")
            return nil
        }
        return bundleAsset.downloadURL
    }

    func installFromBundle(bundleURL: URL,
                           version: String,
                           temporaryDirectory: TemporaryDirectory) throws {
        try versionsController.install(version: version, installation: { installationDirectory in

            // Download bundle
            Printer.shared.print("Downloading version from \(bundleURL.absoluteString)")
            let downloadPath = temporaryDirectory.path.appending(component: Constants.bundleName)
            try System.shared.run("/usr/bin/curl", "-LSs", "--output", downloadPath.pathString, bundleURL.absoluteString)

            // Unzip
            Printer.shared.print("Installing...")
            try System.shared.run("/usr/bin/unzip", "-q", downloadPath.pathString, "-d", installationDirectory.pathString)

            try createTuistVersionFile(version: version, path: installationDirectory)
            Printer.shared.print("Version \(version) installed")
        })
    }

    func installFromSource(version: String,
                           temporaryDirectory: TemporaryDirectory) throws {
        try versionsController.install(version: version) { installationDirectory in
            // Paths
            let buildDirectory = temporaryDirectory.path.appending(RelativePath(".build/release/"))

            // Cloning and building
            Printer.shared.print("Pulling source code")
            try System.shared.run("/usr/bin/env", "git", "clone", Constants.gitRepositoryURL, temporaryDirectory.path.pathString)

            do {
                try System.shared.run("/usr/bin/env", "git", "-C", temporaryDirectory.path.pathString, "checkout", version)
            } catch let error as TuistSupport.SystemError {
                if error.description.contains("did not match any file(s) known to git") {
                    throw InstallerError.versionNotFound(version)
                }
                throw error
            }

            Printer.shared.print("Building using Swift (it might take a while)")
            let swiftPath = try System.shared.capture("/usr/bin/xcrun", "-f", "swift").spm_chuzzle()!

            try System.shared.run(swiftPath, "build",
                                  "--product", "tuist",
                                  "--package-path", temporaryDirectory.path.pathString,
                                  "--configuration", "release")

            try System.shared.run(swiftPath, "build",
                                  "--product", "ProjectDescription",
                                  "--package-path", temporaryDirectory.path.pathString,
                                  "--configuration", "release",
                                  "-Xswiftc", "-enable-library-evolution",
                                  "-Xswiftc", "-emit-module-interface",
                                  "-Xswiftc", "-emit-module-interface-path",
                                  "-Xswiftc", temporaryDirectory.path.appending(RelativePath(".build/release/ProjectDescription.swiftinterface")).pathString) // swiftlint:disable:this line_length

            if FileHandler.shared.exists(installationDirectory) {
                try FileHandler.shared.delete(installationDirectory)
            }
            try FileHandler.shared.createFolder(installationDirectory)

            try buildCopier.copy(from: buildDirectory,
                                 to: installationDirectory)

            try createTuistVersionFile(version: version, path: installationDirectory)
            Printer.shared.print("Version \(version) installed")
        }
    }

    private func createTuistVersionFile(version: String, path: AbsolutePath) throws {
        let tuistVersionPath = path.appending(component: Constants.versionFileName)
        try "\(version)".write(to: tuistVersionPath.url,
                               atomically: true,
                               encoding: .utf8)
    }
}
