import ArgumentParser
import Foundation
import TSCBasic

/// Command that builds a target from the project in the current directory.
struct LintCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "lint",
                             abstract: "A set of tools for linting projects and code.", subcommands: [
                                 LintProjectCommand.self,
                                 LintCodeCommand.self,
                             ])
    }
}
