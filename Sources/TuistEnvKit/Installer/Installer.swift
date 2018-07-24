import Basic
import Foundation
import TuistCore

protocol Installing: AnyObject {
    func install(version: String) throws
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
            if printing { printer.print("Cloning repository") }
            try system.capture3("git", "clone", Constants.gitRepositorySSH, temporaryDirectory.path.asString, verbose: verbose).throwIfError()
            if printing { printer.print("Checking out \(version) reference") }
            try system.capture3("git", "-C", temporaryDirectory.path.asString, "checkout", version, verbose: verbose).throwIfError()
            if printing { printer.print("Building using Swift (it might take a while)") }
            let os = ProcessInfo.processInfo.operatingSystemVersion
            let target = "x86_64-apple-macosx\(os.majorVersion).\(os.minorVersion)"
            try system.capture3("swift", "build",
                                "--package-path", temporaryDirectory.path.asString,
                                "--configuration", "release",
                                "-Xswiftc", "-static-stdlib",
                                "-Xswiftc", "-target",
                                "-Xswiftc", target,
                                verbose: verbose).throwIfError()

            // Copying built files
            try fileHandler.createFolder(installationDirectory)
            try buildCopier.copy(from: buildDirectory,
                                 to: installationDirectory)

            // Create .tuist-version file
            let tuistVersionPath = installationDirectory.appending(component: Constants.versionFileName)
            try "\(version)".write(to: tuistVersionPath.url, atomically: true, encoding: .utf8)

            if printing { printer.print("Version \(version) installed.") }
        }
    }
}
