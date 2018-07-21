import Basic
import Foundation
import Utility
import xpmcore

class CreateIssueCommand: NSObject, Command {
    static let createIssueUrl: String = "https://github.com/xcode-project-manager/xpm/issues/new"

    // MARK: - Command

    static let command = "create-issue"
    static let overview = "Opens the GitHub page to create a new issue."
    let context: CommandsContexting

    // MARK: - Init

    required init(parser: ArgumentParser) {
        parser.add(subparser: CreateIssueCommand.command, overview: CreateIssueCommand.overview)
        context = CommandsContext()
    }

    init(context: CommandsContexting) {
        self.context = context
    }

    // MARK: - Command

    func run(with _: ArgumentParser.Result) throws {
        _ = try context.shell.run("open", CreateIssueCommand.createIssueUrl, environment: [:])
    }
}
