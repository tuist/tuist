import ArgumentParser
import Foundation
import Path

struct GradleCacheCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "cache",
            abstract: "Get Gradle build cache configuration for your project.",
            discussion: """
            Returns the cache endpoint URL and authentication token for configuring
            Gradle's HTTP build cache with Tuist.

            The output can be used to configure the Tuist Gradle plugin or to manually
            set up Gradle's build cache in your settings.gradle file.
            """
        )
    }

    @Argument(
        help: "The full handle of the project (account-handle/project-handle)."
    )
    var fullHandle: String

    @Flag(
        help: "Output the result in JSON format.",
        envKey: .gradleCacheJson
    )
    var json: Bool = false

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .gradleCachePath
    )
    var path: String?

    func run() async throws {
        try await GradleCacheService().run(
            fullHandle: fullHandle,
            json: json,
            directory: path
        )
    }
}
