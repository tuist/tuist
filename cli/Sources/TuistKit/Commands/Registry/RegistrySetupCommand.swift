import ArgumentParser
import Foundation

struct RegistrySetupCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "setup",
            _superCommandName: "registry",
            abstract: "Set up the Tuist Registry."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project to set up the registry for.",
        completion: .directory,
        envKey: .registrySetUpPath
    )
    var path: String?

    func run() async throws {
        try await RegistrySetupCommandService().run(
            path: path
        )
    }
}
