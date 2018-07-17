import Basic
import Foundation
import xpmcore

/// The class that conforms this protocol exposes an interface to install versions of xpm.
protocol Installing: AnyObject {
    /// Installs the version with the given reference in the local environment.
    /// It checks out the git revision and builds it using the Swift compiler.
    ///
    /// - Parameter version: reference to be installed. It can be a commit sha or a git tag.
    /// - Throws: an error if the installation fails. It can happen if the repository cannot be cloned, the reference doesn't exist, or the compilation fails.
    func install(version: String) throws
}

/// Util to install versions of xpm in the local environment.
final class Installer: Installing {

    // MARK: - Attributes

    /// Shell.
    let shell: Shelling

    /// Printer.
    let printer: Printing

    /// File handler.
    let fileHandler: FileHandling

    /// Build copier.
    let buildCopier: BuildCopying

    /// Versions controller.
    let versionsController: VersionsControlling

    // MARK: - Init

    /// Initializes the installer with its attributes.
    ///
    /// - Parameters:
    ///   - shell: shell.
    ///   - printer: printer.
    ///   - fileHandler: file handler.
    ///   - buildCopier: build copier.
    ///   - versionsController: versions controller.
    init(shell: Shelling = Shell(),
         printer: Printing = Printer(),
         fileHandler: FileHandling = FileHandler(),
         buildCopier: BuildCopying = BuildCopier(),
         versionsController: VersionsControlling = VersionsController()) {
        self.shell = shell
        self.printer = printer
        self.fileHandler = fileHandler
        self.buildCopier = buildCopier
        self.versionsController = versionsController
    }

    // MARK: - Installing

    /// Installs the version with the given reference in the local environment.
    /// It checks out the git revision and builds it using the Swift compiler.
    ///
    /// - Parameter version: reference to be installed. It can be a commit sha or a git tag.
    /// - Throws: an error if the installation fails. It can happen if the repository cannot be cloned, the reference doesn't exist, or the compilation fails.
    func install(version: String) throws {
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        try install(version: version, temporaryDirectory: temporaryDirectory)
    }

    /// Installs the version with the given reference in the local environment.
    /// It checks out the git revision and builds it using the Swift compiler.
    ///
    /// - Parameters:
    ///   - version: reference to be installed. It can be a commit sha or a git tag.
    ///   - temporaryDirectory: temporary directory used to download and build xpm.
    /// - Throws: an error if the installation fails. It can happen if the repository cannot be cloned, the reference doesn't exist, or the compilation fails.
    func install(version: String,
                 temporaryDirectory: TemporaryDirectory) throws {
        try versionsController.install(version: version) { installationDirectory in
            // Paths
            let gitDirectory = temporaryDirectory.path.appending(component: ".git")
            let buildDirectory = temporaryDirectory.path.appending(RelativePath(".build/release/"))

            printer.print("Installing \(version) at path \(installationDirectory.asString).")

            // Delete installation directory if it exists
            if fileHandler.exists(installationDirectory) {
                try fileHandler.delete(installationDirectory)
            }

            // Cloning and building
            try shell.run(["git", "clone", Constants.gitRepositorySSH, temporaryDirectory.path.asString], environment: [:])
            try shell.run("git", "--git-dir", gitDirectory.asString, "checkout", version, environment: [:])
            try shell.run("xcrun", "swift", "build", "--package-path", temporaryDirectory.path.asString, "--configuration", "release", environment: [:])

            // Copying built files
            try fileHandler.createFolder(installationDirectory)
            try buildCopier.copy(from: buildDirectory,
                                 to: installationDirectory)

            // Create .xpm-version file
            let xpmVersionPath = installationDirectory.appending(component: Constants.versionFileName)
            try "\(version)".write(to: xpmVersionPath.url, atomically: true, encoding: .utf8)

            printer.print("Version \(version) installed.")
        }
    }
}
