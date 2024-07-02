import ArgumentParser
import Foundation
import Path

struct OrganizationUpdateCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "update",
            _superCommandName: "organization",
            abstract: "A set of commands to update the organization.",
            subcommands: [
                OrganizationUpdateMemberCommand.self,
                OrganizationUpdateSSOCommand.self,
            ]
        )
    }
}
