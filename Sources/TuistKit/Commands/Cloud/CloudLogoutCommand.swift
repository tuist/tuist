#if canImport(TuistCloud)
    import ArgumentParser
    import Foundation
    import TSCBasic

    struct CloudLogoutCommand: ParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "logout",
                _superCommandName: "cloud",
                abstract: "Removes an existing Cloud session."
            )
        }

        @Option(
            name: .shortAndLong,
            help: "The path to the directory or a subdirectory of the project.",
            completion: .directory
        )
        var path: String?

        func run() throws {
            try CloudLogoutService().logout(
                directory: path
            )
        }
    }
#endif
