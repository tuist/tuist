import ArgumentParser
import Foundation

public struct OrganizationUpdateCommand: ParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
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
