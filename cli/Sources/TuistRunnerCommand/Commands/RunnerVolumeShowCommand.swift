import ArgumentParser
import Foundation
import TuistNooraExtension

public struct RunnerVolumeShowCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(commandName: "show", abstract: "Show volume details.")

    @Argument(help: "Volume UUID.")
    var volumeID: String

    @OptionGroup var options: RunnerVolumeOptions

    public var jsonThroughNoora: Bool { true }

    public func validate() throws {
        try RunnerVolumeValidation.validateID(volumeID)
    }

    public func run() async throws {
        try await RunnerVolumeShowCommandService().run(
            volumeID: volumeID,
            account: options.account,
            path: options.path,
            json: options.json
        )
    }
}
