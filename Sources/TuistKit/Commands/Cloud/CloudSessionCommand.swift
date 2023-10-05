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
            name: .long,
            help: "URL to the cloud server."
        )
        var serverURL: String?

        func run() throws {
            try CloudSessionService().printSession(
                serverURL: serverURL
            )
        }
    }
#endif
