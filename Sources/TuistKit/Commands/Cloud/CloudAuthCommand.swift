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
            name: .long,
            help: "URL to the cloud server."
        )
        var serverURL: String?

        func run() throws {
            try CloudAuthService().authenticate(
                serverURL: serverURL
            )
        }
    }
#endif
