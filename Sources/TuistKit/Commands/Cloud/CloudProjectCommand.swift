import ArgumentParser
import Foundation
import TSCBasic

struct CloudProjectCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "project",
            _superCommandName: "cloud",
            abstract: "A set of commands to manage your cloud projects (cloudNext beta flag required in Config.swift).",
            subcommands: [
                CloudProjectCreateCommand.self,
            ]
        )
    }
}
