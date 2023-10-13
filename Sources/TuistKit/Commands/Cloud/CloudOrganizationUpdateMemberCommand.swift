#if canImport(TuistCloud)
    import ArgumentParser
    import Foundation
    import TSCBasic
    import TuistCloud
    import TuistSupport

    struct CloudOrganizationUpdateMemberCommand: AsyncParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "member",
                _superCommandName: "remove",
                abstract: "Update a member from your organization."
            )
        }

        @Argument(
            help: "The name of the organization for which you want to update the member for."
        )
        var organizationName: String

        @Argument(
            help: "The username of the member you want to update."
        )
        var username: String

        @Option(
            help: "The new member role",
            completion: .list(["admin", "user"])
        )
        var role: String

        @Option(
            name: .shortAndLong,
            help: "The path to the directory or a subdirectory of the project.",
            completion: .directory
        )
        var path: String?

        func run() async throws {
            try await CloudOrganizationUpdateMemberService().run(
                organizationName: organizationName,
                username: username,
                role: role,
                directory: path
            )
        }
    }
#endif
