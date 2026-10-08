import ArgumentParser
import Foundation
import TuistNooraExtension

public struct RunnerVolumeClearCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "clear",
        abstract: "Clear saved contents. Running jobs keep their copies but cannot save them."
    )

    @Argument(help: "Volume UUID.")
    var volumeID: String

    @OptionGroup var options: RunnerVolumeOptions

    @Flag(name: .long, help: "Confirm clearing the saved contents. This cannot be undone.")
    var yes = false

    public var jsonThroughNoora: Bool { true }

    public func validate() throws {
        try RunnerVolumeValidation.validateID(volumeID)
        guard yes else { throw ValidationError("Pass --yes to confirm clearing the volume's saved contents.") }
    }

    public func run() async throws {
        try await RunnerVolumeClearCommandService().run(
            volumeID: volumeID,
            account: options.account,
            path: options.path,
            json: options.json
        )
    }
}
