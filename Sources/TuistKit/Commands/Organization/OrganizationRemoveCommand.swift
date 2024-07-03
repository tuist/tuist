import ArgumentParser
import Foundation
import Path

struct OrganizationRemoveCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "remove",
            _superCommandName: "organization",
            abstract: "A set of commands to remove members or cancel pending invitations.",
            subcommands: [
                OrganizationRemoveInviteCommand.self,
                OrganizationRemoveMemberCommand.self,
                OrganizationRemoveSSOCommand.self,
            ]
        )
    }
}
