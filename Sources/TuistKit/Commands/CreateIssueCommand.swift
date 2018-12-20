import Basic
import Foundation
import TuistCore
import Utility

class CreateIssueCommand: NSObject, Command {
    static let createIssueUrl: String = "https://github.com/tuist/tuist/issues/new"

    // MARK: - Command

    static let command = "create-issue"
    static let overview = "Opens the GitHub page to create a new issue."

    // MARK: - Attributes

    private let system: Systeming

    // MARK: - Init

    required init(parser: ArgumentParser) {
        parser.add(subparser: CreateIssueCommand.command, overview: CreateIssueCommand.overview)
        system = System()
    }

    init(system: Systeming) {
        self.system = system
    }

    // MARK: - Command

    func run(with _: ArgumentParser.Result) throws {
        try system.run("/usr/bin/open", CreateIssueCommand.createIssueUrl)
    }
}
