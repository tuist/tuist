import Basic
import Foundation
import Utility

/// Command that opens the issue creation website on GitHub.
public class CreateIssueCommand: NSObject, Command {

    static let issueURL: String = "https://github.com/xcbuddy/xcbuddy/issues/new"
    
    // MARK: - Command

    /// Command name.
    public static let command = "create-issue"

    /// Command description.
    public static let overview = "Opens the GitHub page to create a new issue"

    /// Context
    let context: CommandsContexting

    /// Initializes the command with the argument parser.
    ///
    /// - Parameter parser: argument parser.
    public required init(parser: ArgumentParser) {
        parser.add(subparser: CreateIssueCommand.command, overview: CreateIssueCommand.overview)
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
    public func run(with _: ArgumentParser.Result) throws {
        _ = try context.shell.run("open", issueURL)
    }
}
