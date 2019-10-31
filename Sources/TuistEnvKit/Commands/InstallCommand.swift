import Foundation
import SPMUtility
import TuistSupport

/// Command that installs new versions of Tuist in the system.
final class InstallCommand: Command {
    // MARK: - Command

    /// Command name.
    static var command: String = "install"

    /// Command description.
    static var overview: String = "Installs a version of tuist"

    // MARK: - Attributes

    /// Controller to manage system versions.
    private let versionsController: VersionsControlling

    /// Installer instance to run the installation.
    private let installer: Installing

    /// Version argument to specify the version that will be installed.
    let versionArgument: PositionalArgument<String>

    /// Force argument (-f). When passed, it re-installs the version compiling it from the source.
    let forceArgument: OptionArgument<Bool>

    // MARK: - Init

    convenience init(parser: ArgumentParser) {
        self.init(parser: parser,
                  versionsController: VersionsController(),
                  installer: Installer())
    }

    init(parser: ArgumentParser,
         versionsController: VersionsControlling,
         installer: Installing) {
        let subParser = parser.add(subparser: InstallCommand.command,
                                   overview: InstallCommand.overview)
        self.versionsController = versionsController
        self.installer = installer
        versionArgument = subParser.add(positional: "version",
                                        kind: String.self,
                                        optional: false,
                                        usage: "The version of tuist to be installed")
        forceArgument = subParser.add(option: "--force",
                                      shortName: "-f",
                                      kind: Bool.self,
                                      usage: "Re-installs the version compiling it from the source", completion: nil)
    }

    /// Runs the install command.
    ///
    /// - Parameter result: Result obtained from parsing the CLI arguments.
    /// - Throws: An error if the installation process fails.
    func run(with result: ArgumentParser.Result) throws {
        let force = result.get(forceArgument) ?? false
        let version = result.get(versionArgument)!
        let versions = versionsController.versions().map { $0.description }
        if versions.contains(version) {
            Printer.shared.print(warning: "Version \(version) already installed, skipping")
            return
        }
        try installer.install(version: version, force: force)
    }
}
