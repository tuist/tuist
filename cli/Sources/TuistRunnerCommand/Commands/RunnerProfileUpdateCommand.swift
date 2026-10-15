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
        help: "Branch name or * pattern whose jobs save the profile's cache volumes. Repeat for several branches. Replaces the current list."
    )
    var saveCacheFrom: [String] = []

    @Flag(
        name: .customLong("save-cache-from-default-branch"),
        help: "Follow each repository's default branch instead of a list."
    )
    var saveCacheFromDefaultBranch = false

    @OptionGroup var options: RunnerProfileOptions

    public var jsonThroughNoora: Bool { true }

    public func validate() throws {
        guard saveCacheFrom.isEmpty == saveCacheFromDefaultBranch else {
            throw ValidationError("Pass either --save-cache-from or --save-cache-from-default-branch.")
        }
    }

    public func run() async throws {
        try await RunnerProfileUpdateCommandService().run(
            name: name,
            branches: saveCacheFromDefaultBranch ? nil : saveCacheFrom,
            account: options.account,
            path: options.path,
            json: options.json
        )
    }
}
