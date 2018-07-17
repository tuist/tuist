import Basic
import Foundation
import Utility
import xpmcore

/// Error thrown by the BundleCommand
///
/// - missingVersionFile: Thrown when the developer runs the command in a directory where there isn't a .xpm-version file.
enum BundleCommandError: FatalError, Equatable {
    case missingVersionFile(AbsolutePath)

    var type: ErrorType {
        switch self {
        case .missingVersionFile:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .missingVersionFile(path):
            return "Couldn't find a .xpm-version file in the directory \(path.asString)."
        }
    }

    static func == (lhs: BundleCommandError, rhs: BundleCommandError) -> Bool {
        switch (lhs, rhs) {
        case let (.missingVersionFile(lhsPath), .missingVersionFile(rhsPath)):
            return lhsPath == rhsPath
        }
    }
}

/// Command that bundles the xpm binary in a .xpm-bin in the current directory.
final class BundleCommand: Command {
    /// Command name.
    static var command: String = "bundle"

    /// Command overview.
    static var overview: String = "Bundles the version specified in the .xpm-version file into the .xpm-bin directory."

    /// Versions controller.
    private let versionsController: VersionsControlling

    /// File handler.
    private let fileHandler: FileHandling

    /// Installer.
    private let installer: Installing

    /// Printer.
    private let printer: Printing

    /// Initializes the command with its attributes.
    ///
    /// - Parameter parser: argument parser.
    convenience init(parser: ArgumentParser) {
        self.init(parser: parser,
                  versionsController: VersionsController(),
                  fileHandler: FileHandler(),
                  printer: Printer(),
                  installer: Installer())
    }

    /// Initializes the command with its attributes.
    ///
    /// - Parameters:
    ///   - parser: argument parser.
    ///   - versionsController: versions controller.
    ///   - fileHandler: file handler.
    ///   - printer: printer.
    ///   - installer: installer.
    init(parser: ArgumentParser,
         versionsController: VersionsControlling,
         fileHandler: FileHandling,
         printer: Printing,
         installer: Installing) {
        _ = parser.add(subparser: BundleCommand.command, overview: BundleCommand.overview)
        self.versionsController = versionsController
        self.fileHandler = fileHandler
        self.printer = printer
        self.installer = installer
    }

    /// Runs the command used the argument parser result.
    ///
    /// - Parameter arguments: parsed arguments.
    /// - Throws: an error if the bundling process fails.
    func run(with _: ArgumentParser.Result) throws {
        let versionFilePath = fileHandler.currentPath.appending(component: Constants.versionFileName)
        let binFolderPath = fileHandler.currentPath.appending(component: Constants.binFolderName)

        if !fileHandler.exists(versionFilePath) {
            throw BundleCommandError.missingVersionFile(fileHandler.currentPath)
        }

        let version = try String(contentsOf: versionFilePath.url)
        printer.print(section: "Bundling the version \(version) in the directory \(binFolderPath.asString).")

        let versionPath = versionsController.path(version: version)

        // Installing
        if !fileHandler.exists(versionPath) {
            printer.print("Version \(version) not available locally. Installing...")
            try installer.install(version: version)
        }

        // Copying
        if fileHandler.exists(binFolderPath) {
            try fileHandler.delete(binFolderPath)
        }
        try fileHandler.copy(from: versionPath, to: binFolderPath)

        printer.print(success: "xpm bundled successfully at \(binFolderPath.asString).")
    }
}
