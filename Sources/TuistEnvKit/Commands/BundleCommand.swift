import Basic
import Foundation
import TuistCore
import Utility

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
            return "Couldn't find a .tuist-version file in the directory \(path.asString)"
        }
    }

    static func == (lhs: BundleCommandError, rhs: BundleCommandError) -> Bool {
        switch (lhs, rhs) {
        case let (.missingVersionFile(lhsPath), .missingVersionFile(rhsPath)):
            return lhsPath == rhsPath
        }
    }
}

final class BundleCommand: Command {
    // MARK: - Command

    static var command: String = "bundle"
    static var overview: String = "Bundles the version specified in the .tuist-version file into the .tuist-bin directory"

    // MARK: - Attributes

    private let versionsController: VersionsControlling
    private let fileHandler: FileHandling
    private let installer: Installing
    private let printer: Printing

    // MARK: - Init

    convenience init(parser: ArgumentParser) {
        self.init(parser: parser,
                  versionsController: VersionsController(),
                  fileHandler: FileHandler(),
                  printer: Printer(),
                  installer: Installer())
    }

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

    // MARK: - Internal

    func run(with _: ArgumentParser.Result) throws {
        let versionFilePath = fileHandler.currentPath.appending(component: Constants.versionFileName)
        let binFolderPath = fileHandler.currentPath.appending(component: Constants.binFolderName)

        if !fileHandler.exists(versionFilePath) {
            throw BundleCommandError.missingVersionFile(fileHandler.currentPath)
        }

        let version = try String(contentsOf: versionFilePath.url)
        printer.print(section: "Bundling the version \(version) in the directory \(binFolderPath.asString)")

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

        printer.print(success: "tuist bundled successfully at \(binFolderPath.asString)")
    }
}
