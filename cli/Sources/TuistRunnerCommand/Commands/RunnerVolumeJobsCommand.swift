import ArgumentParser
import Foundation
import TuistNooraExtension

public struct RunnerVolumeJobsCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(commandName: "jobs", abstract: "Show jobs that used a volume.")

    @Argument(help: "Volume UUID.")
    var volumeID: String

    @OptionGroup var options: RunnerVolumeOptions

    @OptionGroup var pagination: RunnerVolumePagination

    public var jsonThroughNoora: Bool { true }

    public func validate() throws {
        try RunnerVolumeValidation.validateID(volumeID)
    }

    public func run() async throws {
        try await RunnerVolumeJobsCommandService().run(
            volumeID: volumeID,
            account: options.account,
            path: options.path,
            page: pagination.page,
            pageSize: pagination.pageSize,
            json: options.json
        )
    }
}
