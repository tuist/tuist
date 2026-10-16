import ArgumentParser
import Foundation
import TuistNooraExtension

public struct RunnerProfileUpdateCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Choose which branches save the profile's cache volumes."
    )

    @Argument(help: "Profile name, without the runs-on label prefix.")
    var name: String

    @Option(
        name: .customLong("save-cache-from"),
        help: "Additional branch name or * pattern whose jobs save the profile's cache volumes. Repeat for several branches. Replaces the current list; omit it to save only from each repository's default branch."
    )
    var saveCacheFrom: [String] = []

    @Flag(
        inversion: .prefixedNo,
        help: "Whether jobs on each repository's default branch save the profile's cache volumes."
    )
    var saveCacheFromDefaultBranch = true

    @OptionGroup var options: RunnerProfileOptions

    public var jsonThroughNoora: Bool { true }

    public func run() async throws {
        try await RunnerProfileUpdateCommandService().run(
            name: name,
            defaultBranch: saveCacheFromDefaultBranch,
            branches: saveCacheFrom,
            account: options.account,
            path: options.path,
            json: options.json
        )
    }
}
