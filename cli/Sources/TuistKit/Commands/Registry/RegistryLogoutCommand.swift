import ArgumentParser
import Foundation

struct RegistryLogoutCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "logout",
            _superCommandName: "registry",
            abstract: "Log out of the registry."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project to which registry you want to log out of.",
        completion: .directory,
        envKey: .registryLogoutPath
    )
    var path: String?

    func run() async throws {
        try await RegistryLogoutService().run(
            path: path
        )
    }
}
