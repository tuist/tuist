@_exported import ArgumentParser
import Foundation
import Path
import TuistConstants
import TuistEnvironment
import TuistLogging

public struct TuistLinuxCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
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

    public static func main(_ arguments: [String]? = nil) async throws {
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
