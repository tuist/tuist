import Basic
import Foundation
import TuistCore

protocol Installing: AnyObject {
    func install(version: String) throws
}

enum InstallerError: FatalError, Equatable {
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

    static func == (lhs: InstallerError, rhs: InstallerError) -> Bool {
        switch (lhs, rhs) {
        case let (.versionNotFound(lhsVersion), .versionNotFound(rhsVersion)):
            return lhsVersion == rhsVersion
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

    // MARK: - Init

    init(system: Systeming = System(),
         printer: Printing = Printer(),
         fileHandler: FileHandling = FileHandler(),
         buildCopier: BuildCopying = BuildCopier(),
         versionsController: VersionsControlling = VersionsController(),
         githubClient: GitHubClienting = GitHubClient()) {
        self.system = system
        self.printer = printer
        self.fileHandler = fileHandler
        self.buildCopier = buildCopier
        self.versionsController = versionsController
        self.githubClient = githubClient
    }

    // MARK: - Installing

    func install(version: String) throws {
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        try install(version: version, temporaryDirectory: temporaryDirectory)
    }

    func install(version: String, temporaryDirectory: TemporaryDirectory) throws {
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
            printer.print(warning: "The release \(version) couldn't be obtained from GitHub")
            return nil
        }
        guard let bundleAsset = release.assets.first(where: { $0.name == Constants.bundleName }) else {
            printer.print(warning: "The release \(version) is not bundled")
            return nil
        }
        return bundleAsset.downloadURL
    }

    func installFromBundle(bundleURL: URL,
                           version: String,
                           temporaryDirectory: TemporaryDirectory) throws {
        try versionsController.install(version: version, installation: { installationDirectory in

            // Download bundle
            printer.print("Downloading version from \(bundleURL.absoluteString)")
            let downloadPath = temporaryDirectory.path.appending(component: Constants.bundleName)
            try system.capture("curl", "-LSs", "--output", downloadPath.asString, bundleURL.absoluteString, verbose: false).throwIfError()

            // Unzip
            printer.print("Installing...")
            try system.capture("unzip", downloadPath.asString, "-d", installationDirectory.asString, verbose: true).throwIfError()

            try createTuistVersionFile(version: version, path: installationDirectory)
            printer.print("Version \(version) installed")
        })
    }

    func installFromSource(version: String,
                           temporaryDirectory: TemporaryDirectory) throws {
        try versionsController.install(version: version) { installationDirectory in
            // Paths
            let buildDirectory = temporaryDirectory.path.appending(RelativePath(".build/release/"))

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

            // Copying files
            try system.capture("/bin/mkdir", installationDirectory.asString, verbose: false).throwIfError()
            try buildCopier.copy(from: buildDirectory,
                                 to: installationDirectory)

            try createTuistVersionFile(version: version, path: installationDirectory)
            printer.print("Version \(version) installed")
        }
    }

    private func createTuistVersionFile(version: String, path: AbsolutePath) throws {
        let tuistVersionPath = path.appending(component: Constants.versionFileName)
        try "\(version)".write(to: tuistVersionPath.url,
                               atomically: true,
                               encoding: .utf8)
    }
}
