import ArgumentParser
import Foundation

public struct OrganizationCommand: ParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "organization",
            abstract: "A set of commands to manage your Tuist organizations.",
            subcommands: [
                OrganizationCreateCommand.self,
                OrganizationListCommand.self,
                OrganizationDeleteCommand.self,
                OrganizationShowCommand.self,
                OrganizationInviteCommand.self,
                OrganizationRemoveCommand.self,
                OrganizationUpdateCommand.self,
                OrganizationBillingCommand.self,
            ]
        )
    }
}
