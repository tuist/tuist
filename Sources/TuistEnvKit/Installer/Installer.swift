import Basic
import Foundation
import TuistCore

protocol Installing: AnyObject {
    func install(version: String) throws
}

enum InstallerError: FatalError {
    case versionNotFound(String)

    var type: ErrorType {
        switch self {
        case .versionNotFound: return .abort
        }
    }

    var description: String {
        switch self {
        case let .versionNotFound(version):
            return "Version \(version) not found."
        }
    }
}

final class Installer: Installing {

    // MARK: - Attributes

    let system: Systeming
    let printer: Printing
    let fileHandler: FileHandling
    let buildCopier: BuildCopying
    let versionsController: VersionsControlling
    let githubClient: GitHubClienting
    let githubRequestsFactory: GitHubRequestsFactory

    // MARK: - Init

    init(system: Systeming = System(),
         printer: Printing = Printer(),
         fileHandler: FileHandling = FileHandler(),
         buildCopier: BuildCopying = BuildCopier(),
         versionsController: VersionsControlling = VersionsController(),
         githubClient: GitHubClienting = GitHubClient(),
         githubRequestsFactory: GitHubRequestsFactory = GitHubRequestsFactory()) {
        self.system = system
        self.printer = printer
        self.fileHandler = fileHandler
        self.buildCopier = buildCopier
        self.versionsController = versionsController
        self.githubClient = githubClient
        self.githubRequestsFactory = githubRequestsFactory
    }

    // MARK: - Installing

    func install(version: String) throws {
        do {
            if let bundleURL = try self.bundleURL(version: version) {
                try installFromBundle(bundleURL: bundleURL, version: version)
            } else {
                try installFromSource(version: version)
            }
        } catch {
            try installFromSource(version: version)
        }
    }

    func bundleURL(version: String) throws -> URL? {
        let release = try githubClient.release(tag: version)
        guard let bundleAsset = release.assets.first(where: { $0.name == Constants.bundleName }) else {
            return nil
        }
        return bundleAsset.downloadURL
    }

    func installFromBundle(bundleURL: URL, version: String) throws {
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)

        try versionsController.install(version: version, installation: { installationDirectory in
            // Delete installation directory if it exists
            if fileHandler.exists(installationDirectory) {
                try fileHandler.delete(installationDirectory)
            }

            // Download bundle
            printer.print("Downloading version from \(bundleURL.absoluteString)")
            let downloadPath = temporaryDirectory.path.appending(component: Constants.bundleName)
            try system.capture("curl", "-LSs", "--output", downloadPath.asString, bundleURL.absoluteString, verbose: false).throwIfError()

            // Unzip
            printer.print("Installing...")
            try system.capture("unzip", downloadPath.asString, "-d", installationDirectory.asString, verbose: true).throwIfError()

            printer.print("Version \(version) installed.")
        })
    }

    func installFromSource(version: String) throws {
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        try versionsController.install(version: version) { installationDirectory in
            // Paths
            let buildDirectory = temporaryDirectory.path.appending(RelativePath(".build/release/"))

            // Delete installation directory if it exists
            if fileHandler.exists(installationDirectory) {
                try fileHandler.delete(installationDirectory)
            }

            // Cloning and building
            printer.print("Pulling source code")

            try system.capture("git", "clone", Constants.gitRepositoryURL, temporaryDirectory.path.asString, verbose: false).throwIfError()
            do {
                try system.capture("git", "-C", temporaryDirectory.path.asString, "checkout", version, verbose: false).throwIfError()
            } catch let error as SystemError {
                if error.description.contains("did not match any file(s) known to git") {
                    throw InstallerError.versionNotFound(version)
                }
                throw error
            }

            printer.print("Building using Swift (it might take a while)")

            let swiftPath = try system.capture("/usr/bin/xcrun", "-f", "swift", verbose: false).stdout.chuzzle()!
            try system.capture(swiftPath, "build",
                               "--product", "tuist",
                               "--package-path", temporaryDirectory.path.asString,
                               "--configuration", "release",
                               "-Xswiftc", "-static-stdlib",
                               verbose: false).throwIfError()
            try system.capture(swiftPath, "build",
                               "--product", "ProjectDescription",
                               "--package-path", temporaryDirectory.path.asString,
                               "--configuration", "release",
                               verbose: false).throwIfError()

            // Copying built files
            try system.capture("mkdir", installationDirectory.asString, verbose: false).throwIfError()
            try buildCopier.copy(from: buildDirectory,
                                 to: installationDirectory)

            // Create .tuist-version file
            let tuistVersionPath = installationDirectory.appending(component: Constants.versionFileName)
            try "\(version)".write(to: tuistVersionPath.url, atomically: true, encoding: .utf8)

            printer.print("Version \(version) installed.")
        }
    }
}
