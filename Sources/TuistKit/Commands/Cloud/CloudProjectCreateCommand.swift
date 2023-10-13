#if canImport(TuistCloud)
    import ArgumentParser
    import Foundation
    import TSCBasic
    import TuistSupport

    struct CloudProjectCreateCommand: AsyncParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "create",
                _superCommandName: "project",
                abstract: "Create a new project."
            )
        }

        @Argument(
            help: "The name of the project to create.",
            completion: .directory
        )
        var name: String

        @Option(
            name: .shortAndLong,
            help: "Organization to create the project with. If not specified, the project is created with your personal cloud account."
        )
        var organization: String?

        @Option(
            name: .shortAndLong,
            help: "The path to the directory or a subdirectory of the project.",
            completion: .directory
        )
        var path: String?

        func run() async throws {
            try await CloudProjectCreateService().run(
                name: name,
                organization: organization,
                directory: path
            )
        }
    }
#endif
