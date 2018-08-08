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

    // MARK: - Init

    init(system: Systeming = System(),
         printer: Printing = Printer(),
         fileHandler: FileHandling = FileHandler(),
         buildCopier: BuildCopying = BuildCopier(),
         versionsController: VersionsControlling = VersionsController()) {
        self.system = system
        self.printer = printer
        self.fileHandler = fileHandler
        self.buildCopier = buildCopier
        self.versionsController = versionsController
    }

    // MARK: - Installing

    func install(version: String) throws {
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        try install(version: version, temporaryDirectory: temporaryDirectory)
    }

    func install(version: String,
                 temporaryDirectory: TemporaryDirectory,
                 verbose: Bool = false,
                 printing: Bool = true) throws {
        try versionsController.install(version: version) { installationDirectory in
            // Paths
            let buildDirectory = temporaryDirectory.path.appending(RelativePath(".build/release/"))

            // Delete installation directory if it exists
            if fileHandler.exists(installationDirectory) {
                try fileHandler.delete(installationDirectory)
            }

            // Cloning and building
            if printing { printer.print("Pulling source code") }
            try system.capture("git", "clone", Constants.gitRepositorySSH, temporaryDirectory.path.asString, verbose: verbose).throwIfError()
            do {
                try system.capture("git", "-C", temporaryDirectory.path.asString, "checkout", version, verbose: verbose).throwIfError()
            } catch let error as SystemError {
                if error.description.contains("did not match any file(s) known to git") {
                    throw InstallerError.versionNotFound(version)
                }
                throw error
            }

            if printing { printer.print("Building using Swift (it might take a while)") }
            let swiftPath = try system.capture("/usr/bin/xcrun", "-f", "swift", verbose: false).stdout.chuzzle()!
            try system.capture(swiftPath, "build",
                               "--product", "tuist",
                               "--package-path", temporaryDirectory.path.asString,
                               "--configuration", "release",
                               "-Xswiftc", "-static-stdlib",
                               verbose: verbose).throwIfError()
            try system.capture(swiftPath, "build",
                               "--product", "ProjectDescription",
                               "--package-path", temporaryDirectory.path.asString,
                               "--configuration", "release",
                               verbose: verbose).throwIfError()

            // Copying built files
            try system.capture("mkdir", installationDirectory.asString, verbose: verbose).throwIfError()
            try buildCopier.copy(from: buildDirectory,
                                 to: installationDirectory)

            // Create .tuist-version file
            let tuistVersionPath = installationDirectory.appending(component: Constants.versionFileName)
            try "\(version)".write(to: tuistVersionPath.url, atomically: true, encoding: .utf8)

            if printing { printer.print("Version \(version) installed.") }
        }
    }
}
