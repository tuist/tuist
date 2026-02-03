import ArgumentParser
import Foundation

public struct CacheConfigCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
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
        help: "Output the result in JSON format."
    )
    var json: Bool = false

    @Option(
        name: [.customShort("p"), .long],
        help: "The path to the directory containing the Tuist project."
    )
    var path: String?

    @Option(
        name: .long,
        help: "The URL of the server."
    )
    var serverURL: String?

    public func run() async throws {
        try await CacheConfigService().run(
            fullHandle: fullHandle,
            json: json,
            directory: path,
            serverURL: serverURL
        )
    }
}
