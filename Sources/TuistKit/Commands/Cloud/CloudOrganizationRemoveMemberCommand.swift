import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

struct CloudOrganizationRemoveMemberCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "member",
            _superCommandName: "remove",
            abstract: "Remove a member from your organization."
        )
    }

    @Argument(
        help: "The name of the organization to remove the organization member from.",
        envKey: .cloudOrganizationRemoveMemberOrganizationName
    )
    var organizationName: String

    @Argument(
        help: "The username of the member you want to remove from the organization.",
        envKey: .cloudOrganizationRemoveMemberUsername
    )
    var username: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .cloudOrganizationRemoveMemberPath
    )
    var path: String?

    func run() async throws {
        try await CloudOrganizationRemoveMemberService().run(
            organizationName: organizationName,
            username: username,
            directory: path
        )
    }
}
