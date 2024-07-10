import ArgumentParser
import Foundation
import Path
import TuistSupport

struct OrganizationInviteCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "invite",
            _superCommandName: "organization",
            abstract: "Invite a new member to your organization."
        )
    }

    @Argument(
        help: "The name of the organization to invite the user to.",
        envKey: .organizationInviteOrganizationName
    )
    var organizationName: String

    @Argument(
        help: "The email of the user to invite.",
        envKey: .organizationInviteEmail
    )
    var email: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .organizationInvitePath
    )
    var path: String?

    func run() async throws {
        try await OrganizationInviteService().run(
            organizationName: organizationName,
            email: email,
            directory: path
        )
    }
}
