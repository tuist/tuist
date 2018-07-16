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

    /// Environment controller.
    private let environmentController: EnvironmentControlling

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
                  environmentController: EnvironmentController(),
                  fileHandler: FileHandler(),
                  printer: Printer(),
                  installer: Installer())
    }

    /// Initializes the command with its attributes.
    ///
    /// - Parameters:
    ///   - parser: argument parser.
    ///   - environmentController: environment controller.
    ///   - fileHandler: file handler.
    ///   - printer: printer.
    ///   - installer: installer.
    init(parser: ArgumentParser,
         environmentController: EnvironmentControlling,
         fileHandler: FileHandling,
         printer: Printing,
         installer: Installing) {
        _ = parser.add(subparser: BundleCommand.command, overview: BundleCommand.overview)
        self.environmentController = environmentController
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
        printer.print(section: "Bundling the version \(version) in the directory \(binFolderPath.asString)")

        let versionPath = environmentController.path(version: version)

        if !fileHandler.exists(versionPath) {
            printer.print("Version \(version) not available locally. Installing...")
            try installer.install(version: version)
        }

        try fileHandler.copy(from: versionPath, to: binFolderPath)
        printer.print("xpm bundle successfully at \(binFolderPath.asString)")
    }
}
