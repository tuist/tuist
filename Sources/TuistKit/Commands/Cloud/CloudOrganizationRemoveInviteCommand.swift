import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

struct CloudOrganizationRemoveInviteCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "invite",
            _superCommandName: "remove",
            abstract: "Cancel pending invitation."
        )
    }

    @Argument(
        help: "The name of the organization to cancel the invitation for.",
        envKey: .cloudOrganizationRemoveInviteOrganizationName
    )
    var organizationName: String

    @Argument(
        help: "The email of the user to cancel the invitation for.",
        envKey: .cloudOrganizationRemoveInviteEmail
    )
    var email: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .cloudOrganizationRemoveInvitePath
    )
    var path: String?

    func run() async throws {
        try await CloudOrganizationRemoveInviteService().run(
            organizationName: organizationName,
            email: email,
            directory: path
        )
    }
}
