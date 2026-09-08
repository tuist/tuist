import ArgumentParser
import Foundation

extension XcodeCacheUploadPolicy: ExpressibleByArgument {}

struct SetupCacheCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "cache",
            _superCommandName: "setup",
            abstract: "Set up the Tuist Xcode cache",
            discussion: """
            Run without options, this installs the cache agent for the project and records \
            the `xcodeCache(upload:)` policy from 'Tuist.swift'.

            `--upload-policy` changes only that policy, for this machine, and leaves the agent \
            running. The cache proxy re-reads it within 15 seconds. It does not set the cache \
            up, and a plain `tuist setup cache` records the policy from 'Tuist.swift' again, so \
            run the two in that order.

            Two caveats worth knowing before you rely on it:

            - The policy is recorded per machine and per project, not per build. Two lanes \
            building the same project at once on one machine both see whichever policy was \
            written last.

            - `--upload-policy disabled` stops every upload on its own. `--upload-policy \
            enabled` does not start Swift uploads again if the project was generated with \
            `xcodeCache(upload: false)`: `tuist generate` bakes that into the project as a \
            build setting the cache plugin gates on by itself, so the project has to be \
            regenerated with `xcodeCache(upload: true)`.
            """
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory
    )
    var path: String?

    @Option(
        name: .long,
        help: "Change only whether this machine uploads Xcode cache artifacts for the project, without reinstalling the cache agent."
    )
    var uploadPolicy: XcodeCacheUploadPolicy?

    func run() async throws {
        try await SetupCacheCommandService().run(
            path: path,
            uploadPolicy: uploadPolicy
        )
    }
}
