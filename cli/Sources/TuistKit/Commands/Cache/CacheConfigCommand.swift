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
            a build system's HTTP cache with Tuist.

            The output includes the endpoint URL and authentication credentials that can
            be used to configure build caches for various build systems (Gradle, Bazel, etc).
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

    func run() async throws {
        try await CacheConfigService().run(
            fullHandle: fullHandle,
            json: json,
            directory: path
        )
    }
}
