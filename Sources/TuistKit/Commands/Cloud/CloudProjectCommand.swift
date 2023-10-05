#if canImport(TuistCloud)
import ArgumentParser
import Foundation
import TSCBasic

struct CloudProjectCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "project",
            _superCommandName: "cloud",
            abstract: "A set of commands to manage your cloud projects.",
            subcommands: [
                CloudProjectCreateCommand.self,
                CloudProjectListCommand.self,
                CloudProjectDeleteCommand.self,
                CloudProjectTokenCommand.self,
            ]
        )
    }
}
#endif
