#if os(macOS)
    import FileSystem
    import Foundation
    import Noora
    import Path
    import TSCBasic
    import TuistKit
    import TuistSupport

    @main
    @_documentation(visibility: private)
    private enum TuistCLI {
        static func main() async throws {
            try await initDependencies { logFilePath in
                try await TuistCommand.main(logFilePath: logFilePath)
            }
        }
    }
#else
    import ArgumentParser
    import Foundation
    import TuistAuthLoginCommand
    import TuistCacheConfigCommand
    import TuistConstants
    import TuistEnvironment
    import TuistLogging

    @main
    @_documentation(visibility: private)
    private enum TuistCLI {
        static func main() async throws {
            try await TuistLinuxCommand.main()
        }
    }

    struct TuistLinuxCommand: AsyncParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "tuist",
                abstract: "Build better apps faster.",
                subcommands: [
                    AuthCommand.self,
                    CacheCommand.self,
                    VersionCommand.self,
                ]
            )
        }

        static func main(_ arguments: [String]? = nil) async throws {
            let processedArguments = Array(processArguments(arguments)?.dropFirst() ?? [])

            do {
                var command = try parseAsRoot(processedArguments)
                try await command.run()
            } catch {
                Self.exit(withError: error)
            }
        }

        static func processArguments(_ arguments: [String]? = nil) -> [String]? {
            let arguments = arguments ?? Array(Environment.current.arguments)
            return arguments.filter { $0 != "--verbose" && $0 != "--quiet" }
        }
    }

    struct AuthCommand: ParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "auth",
                abstract: "Manage authentication",
                subcommands: [
                    LoginCommand.self,
                ]
            )
        }
    }

    struct CacheCommand: AsyncParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "cache",
                abstract: "Cache management commands.",
                subcommands: [
                    CacheConfigCommand.self,
                ],
                defaultSubcommand: CacheConfigCommand.self
            )
        }
    }

    struct VersionCommand: ParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "version",
                abstract: "Outputs the current version of tuist"
            )
        }

        func run() throws {
            print(Constants.version!)
        }
    }
#endif
