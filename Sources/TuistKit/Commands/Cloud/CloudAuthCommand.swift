#if canImport(TuistCloud)
    import ArgumentParser
    import Foundation
    import TSCBasic

    struct CloudAuthCommand: ParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "auth",
                _superCommandName: "cloud",
                abstract: "Authenticates the user for using Cloud"
            )
        }

        @Option(
            name: .shortAndLong,
            help: "The path to the directory or a subdirectory of the project.",
            completion: .directory
        )
        var path: String?

        func run() throws {
            try CloudAuthService().authenticate(
                directory: path
            )
        }
    }
#endif
