import ArgumentParser
import Foundation
import Path
import TuistSupport

struct OrganizationRemoveInviteCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "invite",
            _superCommandName: "remove",
            abstract: "Cancel pending invitation."
        )
    }

    @Argument(
        help: "The name of the organization to cancel the invitation for.",
        envKey: .organizationRemoveInviteOrganizationName
    )
    var organizationName: String

    @Argument(
        help: "The email of the user to cancel the invitation for.",
        envKey: .organizationRemoveInviteEmail
    )
    var email: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .organizationRemoveInvitePath
    )
    var path: String?

    func run() async throws {
        try await OrganizationRemoveInviteService().run(
            organizationName: organizationName,
            email: email,
            directory: path
        )
    }
}
