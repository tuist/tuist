import ArgumentParser
import Foundation
import TuistEnvKey
import TuistServer

public struct OrganizationInviteCommand: AsyncParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
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
        help: "The role the invitee gets when they accept the invitation. Defaults to user.",
        envKey: .organizationInviteRole
    )
    var role: Operations.createInvitation.Input.Body.jsonPayload.rolePayload?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .organizationInvitePath
    )
    var path: String?

    public func run() async throws {
        try await OrganizationInviteService().run(
            organizationName: organizationName,
            email: email,
            role: role,
            directory: path
        )
    }
}

extension Operations.createInvitation.Input.Body.jsonPayload.rolePayload: @retroactive ExpressibleByArgument {}
