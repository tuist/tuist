import ArgumentParser
import Foundation
import TSCBasic

struct LintCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "lint",
                             abstract: "A set of tools for linting projects and code.",
                             subcommands: [
                                LintProjectCommand.self,
                                LintCodeCommand.self,
                             ])
    }
}
