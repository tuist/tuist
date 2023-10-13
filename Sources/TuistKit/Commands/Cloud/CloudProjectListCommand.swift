#if canImport(TuistCloud)
    import ArgumentParser
    import Foundation
    import TSCBasic
    import TuistSupport

    struct CloudProjectListCommand: AsyncParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "list",
                _superCommandName: "project",
                abstract: "List projects you have access to."
            )
        }

        @Flag(
            help: "The output in JSON format."
        )
        var json: Bool = false

        @Option(
            name: .shortAndLong,
            help: "The path to the directory or a subdirectory of the project.",
            completion: .directory
        )
        var path: String?

        func run() async throws {
            try await CloudProjectListService().run(
                json: json,
                directory: path
            )
        }
    }
#endif
