import Basic
import Foundation
import SPMUtility
import TuistSupport

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
            return "Couldn't find a .tuist-version file in the directory \(path.pathString)"
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
    private let installer: Installing

    // MARK: - Init

    convenience init(parser: ArgumentParser) {
        self.init(parser: parser,
                  versionsController: VersionsController(),
                  installer: Installer())
    }

    init(parser: ArgumentParser,
         versionsController: VersionsControlling,
         installer: Installing) {
        let subParser = parser.add(subparser: BundleCommand.command, overview: BundleCommand.overview)
        self.versionsController = versionsController
        self.installer = installer
    }

    // MARK: - Internal

    func run(with _: ArgumentParser.Result) throws {
        let versionFilePath = FileHandler.shared.currentPath.appending(component: Constants.versionFileName)
        let binFolderPath = FileHandler.shared.currentPath.appending(component: Constants.binFolderName)

        if !FileHandler.shared.exists(versionFilePath) {
            throw BundleCommandError.missingVersionFile(FileHandler.shared.currentPath)
        }

        let version = try String(contentsOf: versionFilePath.url)
        logger.notice("Bundling the version \(version) in the directory \(binFolderPath.pathString)", metadata: .section)

        let versionPath = versionsController.path(version: version)

        // Installing
        if !FileHandler.shared.exists(versionPath) {
            logger.notice("Version \(version) not available locally. Installing...")
            try installer.install(version: version, force: false)
        }

        // Copying
        if FileHandler.shared.exists(binFolderPath) {
            try FileHandler.shared.delete(binFolderPath)
        }
        try FileHandler.shared.copy(from: versionPath, to: binFolderPath)

        logger.notice("tuist bundled successfully at \(binFolderPath.pathString)", metadata: .success)
    }
}
