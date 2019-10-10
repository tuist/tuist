import Basic
import Foundation
import SPMUtility
import TuistCore

class CreateIssueCommand: NSObject, Command {
    static let createIssueUrl: String = "https://github.com/tuist/tuist/issues/new"

    // MARK: - Command

    static let command = "create-issue"
    static let overview = "Opens the GitHub page to create a new issue."

    // MARK: - Init

    required init(parser: ArgumentParser) {
        parser.add(subparser: CreateIssueCommand.command, overview: CreateIssueCommand.overview)
    }

    // MARK: - Command

    func run(with _: ArgumentParser.Result) throws {
        try System.shared.run("/usr/bin/open", CreateIssueCommand.createIssueUrl)
    }
}
