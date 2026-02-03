import ArgumentParser
import Foundation

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

    @Flag(
        help: "Force refresh the authentication token, ignoring any cached credentials.",
        envKey: .cacheConfigForceRefresh
    )
    var forceRefresh: Bool = false

    @Option(
        name: .long,
        help: "The URL of the server. If not provided, it defaults to the Tuist server.",
        envKey: .cacheConfigServerURL
    )
    var url: String?

    func run() async throws {
        try await CacheConfigCommandService().run(
            fullHandle: fullHandle,
            json: json,
            forceRefresh: forceRefresh,
            url: url
        )
    }
}
