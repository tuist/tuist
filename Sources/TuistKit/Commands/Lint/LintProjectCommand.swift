import ArgumentParser
import Foundation
import TSCBasic

/// Command that builds a target from the project in the current directory.
struct LintProjectCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "project",
                             abstract: "Lints a workspace or a project that check whether they are well configured")
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the workspace or project to be linted",
        completion: .directory
    )
    var path: String?

    func run() throws {
        try LintProjectService().run(path: path)
    }
}
