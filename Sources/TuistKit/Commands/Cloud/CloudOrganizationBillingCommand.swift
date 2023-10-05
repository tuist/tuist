#if canImport(TuistCloud)
    import ArgumentParser
    import Foundation
    import TSCBasic
    import TuistSupport

    struct CloudOrganizationBillingCommand: AsyncParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "billing",
                _superCommandName: "organization",
                abstract: "Open billing dashboard for the specified organization."
            )
        }

        @Argument(
            help: "The name of the organization to show billing dashboard for."
        )
        var organizationName: String

        @Option(
            name: .long,
            help: "URL to the cloud server."
        )
        var serverURL: String?

        func run() async throws {
            try await CloudOrganizationBillingService().run(
                organizationName: organizationName,
                serverURL: serverURL
            )
        }
    }
#endif
