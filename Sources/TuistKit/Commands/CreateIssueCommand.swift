import ArgumentParser
import Foundation
import TSCBasic

struct CreateIssueCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "create-issue",
            abstract: "Opens the GitHub page to create a new issue"
        )
    }

    func run() throws {
        try CreateIssueService().run()
    }
}
