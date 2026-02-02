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

            On Linux, the server URL must be specified via the --server-url flag or TUIST_URL
            environment variable since configuration file loading is not supported.
            """
        )
    }

    @Argument(
        help: "The full handle of the project (account-handle/project-handle)."
    )
    var fullHandle: String

    @Flag(
        help: "Output the result in JSON format."
    )
    var json: Bool = false

    @Option(
        name: .long,
        help: "The URL of the server. Required on Linux unless TUIST_URL environment variable is set."
    )
    var serverURL: String?

    func run() async throws {
        try await CacheConfigService().run(
            fullHandle: fullHandle,
            json: json,
            serverURL: serverURL
        )
    }
}
