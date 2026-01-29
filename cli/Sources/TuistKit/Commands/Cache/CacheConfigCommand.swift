import ArgumentParser
import Foundation
import Path

struct CacheConfigCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "config",
            abstract: "Get remote cache configuration for your project.",
            discussion: """
            Returns the cache endpoint URL and authentication token for configuring
            remote build caching with Tuist.

            The output includes the endpoint URL and authentication credentials that can
            be used to configure build caches for supported build systems like Gradle.
            """
        )
    }

    @Argument(
        help: "The full handle of the project (account-handle/project-handle)."
    )
    var fullHandle: String

    @Flag(
        help: "Output the result in JSON format.",
        envKey: .cacheConfigJson
    )
    var json: Bool = false

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .cacheConfigPath
    )
    var path: String?

    @Option(
        name: .long,
        help: "The URL of the server. If not provided, it will be read from the project configuration or default to the Tuist server.",
        envKey: .cacheConfigServerURL
    )
    var serverURL: String?

    func run() async throws {
        try await CacheConfigService().run(
            fullHandle: fullHandle,
            json: json,
            directory: path,
            serverURL: serverURL
        )
    }
}
