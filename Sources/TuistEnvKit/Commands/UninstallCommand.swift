import Foundation
import SPMUtility
import TuistSupport

final class UninstallCommand: Command {
    // MARK: - Command

    static var command: String = "uninstall"
    static var overview: String = "Uninstalls a version of tuist"

    // MARK: - Attributes

    private let versionsController: VersionsControlling
    private let installer: Installing
    let versionArgument: PositionalArgument<String>

    // MARK: - Init

    convenience init(parser: ArgumentParser) {
        self.init(parser: parser,
                  versionsController: VersionsController(),
                  installer: Installer())
    }

    init(parser: ArgumentParser,
         versionsController: VersionsControlling,
         installer: Installing) {
        let subParser = parser.add(subparser: UninstallCommand.command,
                                   overview: UninstallCommand.overview)
        self.versionsController = versionsController
        self.installer = installer
        versionArgument = subParser.add(positional: "version",
                                        kind: String.self,
                                        optional: false,
                                        usage: "The version of tuist to be uninstalled")
    }

    func run(with result: ArgumentParser.Result) throws {
        let version = result.get(versionArgument)!
        let versions = versionsController.versions().map { $0.description }
        if versions.contains(version) {
            try versionsController.uninstall(version: version)
            logger.notice("Version \(version) uninstalled".success())
        } else {
            logger.warning("Version \(version) cannot be uninstalled because it's not installed")
        }
    }
}
