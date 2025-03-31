import ArgumentParser
import Foundation

struct RegistryLoginCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "login",
            _superCommandName: "registry",
            abstract: "Log in to the registry."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project to which registry you want to log in.",
        completion: .directory,
        envKey: .registryLoginPath
    )
    var path: String?

    func run() async throws {
        try await RegistryLoginCommandService().run(
            path: path
        )
    }
}
