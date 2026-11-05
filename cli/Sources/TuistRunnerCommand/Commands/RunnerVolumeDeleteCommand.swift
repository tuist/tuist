import ArgumentParser
import Foundation
import TuistNooraExtension

public struct RunnerVolumeDeleteCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a volume and its saved contents. Running jobs keep their copies but cannot save them.",
        aliases: ["clear"]
    )

    @Argument(help: "Volume UUID.")
    var volumeID: String

    @OptionGroup var options: RunnerVolumeOptions

    @Flag(name: .long, help: "Confirm deleting the volume. This cannot be undone.")
    var yes = false

    public var jsonThroughNoora: Bool { true }

    public func validate() throws {
        try RunnerVolumeValidation.validateID(volumeID)
        guard yes else { throw ValidationError("Pass --yes to confirm deleting the volume.") }
    }

    public func run() async throws {
        try await RunnerVolumeDeleteCommandService().run(
            volumeID: volumeID,
            account: options.account,
            path: options.path,
            json: options.json
        )
    }
}
