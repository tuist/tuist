#if canImport(TuistCloud)
    import ArgumentParser
    import Foundation
    import TSCBasic

    struct CloudSessionCommand: ParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "session",
                _superCommandName: "cloud",
                abstract: "Prints the current Cloud session"
            )
        }

        @Option(
            name: .shortAndLong,
            help: "The path to the directory or a subdirectory of the project.",
            completion: .directory
        )
        var path: String?

        func run() throws {
            try CloudSessionService().printSession(
                directory: path
            )
        }
    }
#endif
