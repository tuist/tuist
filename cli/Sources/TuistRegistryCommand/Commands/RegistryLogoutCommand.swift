#if os(macOS)
    import ArgumentParser
    import Foundation
    import TuistEnvKey

    public struct RegistryLogoutCommand: AsyncParsableCommand {
        public init() {}
        public static var configuration: CommandConfiguration {
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

        public func run() async throws {
            try await RegistryLogoutService().run(
                path: path
            )
        }
    }
#endif
