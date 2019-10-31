import Foundation
import SPMUtility
import TuistSupport

/// Command that updates the version of Tuist in the environment.
final class UpdateCommand: Command {
    // MARK: - Command

    /// Name of the command.
    static var command: String = "update"

    /// Description of the command.
    static var overview: String = "Installs the latest version if it's not already installed"

    // MARK: - Attributes

    /// Updater instance that runs the update.
    private let updater: Updating

    /// Force argument (-f). When passed, it re-installs the latest version compiling it from the source.
    let forceArgument: OptionArgument<Bool>

    // MARK: - Init

    /// Initializes the update command.
    ///
    /// - Parameter parser: Argument parser where the command should be registered.
    convenience init(parser: ArgumentParser) {
        self.init(parser: parser,
                  updater: Updater())
    }

    /// Initializes the update command.
    ///
    /// - Parameters:
    ///   - parser: Argument parser where the command should be registered.
    ///   - updater: Updater instance that runs the update.
    init(parser: ArgumentParser,
         updater: Updating) {
        let subParser = parser.add(subparser: UpdateCommand.command, overview: UpdateCommand.overview)
        self.updater = updater
        forceArgument = subParser.add(option: "--force",
                                      shortName: "-f",
                                      kind: Bool.self,
                                      usage: "Re-installs the latest version compiling it from the source", completion: nil)
    }

    /// Runs the update command.
    ///
    /// - Parameter result: Result obtained from parsing the CLI arguments.
    /// - Throws: An error if the update process fails.
    func run(with result: ArgumentParser.Result) throws {
        let force = result.get(forceArgument) ?? false
        Printer.shared.print(section: "Checking for updates...")
        try updater.update(force: force)
    }
}
