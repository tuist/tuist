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
            name: .shortAndLong,
            help: "The path to the directory or a subdirectory of the project.",
            completion: .directory
        )
        var path: String?

        func run() async throws {
            try await CloudOrganizationBillingService().run(
                organizationName: organizationName,
                directory: path
            )
        }
    }
#endif
