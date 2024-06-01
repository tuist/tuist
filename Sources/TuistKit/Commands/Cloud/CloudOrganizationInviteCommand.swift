import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

struct CloudOrganizationInviteCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "invite",
            _superCommandName: "organization",
            abstract: "Invite a new member to your organization."
        )
    }

    @Argument(
        help: "The name of the organization to invite the user to.",
        envKey: .cloudOrganizationInviteOrganizationName
    )
    var organizationName: String

    @Argument(
        help: "The email of the user to invite.",
        envKey: .cloudOrganizationInviteEmail
    )
    var email: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .cloudOrganizationInvitePath
    )
    var path: String?

    func run() async throws {
        try await CloudOrganizationInviteService().run(
            organizationName: organizationName,
            email: email,
            directory: path
        )
    }
}
