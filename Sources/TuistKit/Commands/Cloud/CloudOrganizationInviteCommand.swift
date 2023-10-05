#if canImport(TuistCloud)
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
            help: "The name of the organization to invite the user to."
        )
        var organizationName: String

        @Argument(
            help: "The email of the user to invite."
        )
        var email: String

        @Option(
            name: .long,
            help: "URL to the cloud server."
        )
        var serverURL: String?

        func run() async throws {
            try await CloudOrganizationInviteService().run(
                organizationName: organizationName,
                email: email,
                serverURL: serverURL
            )
        }
    }
#endif
