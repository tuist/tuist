import ArgumentParser
import Foundation
import TSCBasic

struct CloudOrganizationCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "organization",
            _superCommandName: "cloud",
            abstract: "A set of commands to manage your Cloud organizations.",
            subcommands: [
                CloudOrganizationCreateCommand.self,
                CloudOrganizationListCommand.self,
                CloudOrganizationDeleteCommand.self,
                CloudOrganizationShowCommand.self,
                CloudOrganizationInviteCommand.self,
                CloudOrganizationRemoveCommand.self,
                CloudOrganizationUpdateCommand.self,
            ]
        )
    }
}
