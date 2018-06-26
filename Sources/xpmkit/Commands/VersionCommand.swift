import Basic
import Foundation
import Utility

/// Command that outputs the version of the tool.
public class VersionCommand: NSObject, Command {

    // MARK: - Command

    /// Command name.
    public static let command = "version"

    /// Command description.
    public static let overview = "Outputs the current version of xpm."

    /// Context
    let context: CommandsContexting

    /// Initializes the command with the argument parser.
    ///
    /// - Parameter parser: argument parser.
    public required init(parser: ArgumentParser) {
        parser.add(subparser: VersionCommand.command, overview: VersionCommand.overview)
        context = CommandsContext()
    }

    /// Initializes the command with the context.
    ///
    /// - Parameter context: command context.
    init(context: CommandsContexting) {
        self.context = context
    }

    /// Runs the command.
    ///
    /// - Parameter arguments: input arguments.
    /// - Throws: throws an error if the execution fails.
    public func run(with _: ArgumentParser.Result) {
        context.printer.print(Constants.version)
    }
}
