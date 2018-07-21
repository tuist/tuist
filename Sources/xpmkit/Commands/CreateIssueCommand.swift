import Basic
import Foundation
import Utility
import xpmcore

class CreateIssueCommand: NSObject, Command {
    static let createIssueUrl: String = "https://github.com/xcode-project-manager/xpm/issues/new"

    // MARK: - Command

    static let command = "create-issue"
    static let overview = "Opens the GitHub page to create a new issue."
    
    // MARK: - Attributes
    
    private let shell: Shelling
    
    // MARK: - Init

    required init(parser: ArgumentParser) {
        parser.add(subparser: CreateIssueCommand.command, overview: CreateIssueCommand.overview)
        shell = Shell()
    }

    init(shell: Shelling) {
        self.shell = shell
    }

    // MARK: - Command

    func run(with _: ArgumentParser.Result) throws {
        _ = try shell.run("open", CreateIssueCommand.createIssueUrl, environment: [:])
    }
}
