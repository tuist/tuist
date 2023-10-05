#if canImport(TuistCloud)
    import ArgumentParser
    import Foundation
    import TSCBasic
    import TuistSupport

    struct CloudProjectTokenCommand: AsyncParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "token",
                _superCommandName: "project",
                abstract: "Get a project token. You can save this token in the `TUIST_CONFIG_CLOUD_TOKEN` environment variable to use the remote cache on the CI."
            )
        }

        @Argument(
            help: "The name of the project to get the token for.",
            completion: .directory
        )
        var projectName: String

        @Option(
            name: .shortAndLong,
            help: "Organization of the project. If not specified, it defaults to your user account."
        )
        var organizationName: String?

        @Option(
            name: .long,
            help: "URL to the cloud server."
        )
        var serverURL: String?

        func run() async throws {
            try await CloudProjectTokenService().run(
                projectName: projectName,
                organizationName: organizationName,
                serverURL: serverURL
            )
        }
    }
#endif
