import ArgumentParser
import Foundation
import TuistNooraExtension

enum RunnerVolumeSort: String, ExpressibleByArgument, CaseIterable {
    case volume, repository
    case usedSpace = "used_space"
    case capacity
    case lastUsed = "last_used"
}

enum RunnerVolumeSortOrder: String, ExpressibleByArgument, CaseIterable {
    case asc, desc
}

public struct RunnerVolumeListCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List and filter volumes by name and repository."
    )

    @OptionGroup var options: RunnerVolumeOptions

    @OptionGroup var pagination: RunnerVolumePagination

    @Option(name: .long, help: "Filter by exact volume name (cache key).")
    var name: String?

    @Option(name: .long, help: "Filter by exact repository, including its owner or namespace.")
    var repository: String?

    @Option(name: .long)
    var sortBy: RunnerVolumeSort?

    @Option(name: .long)
    var sortOrder: RunnerVolumeSortOrder?

    public var jsonThroughNoora: Bool { true }

    public func run() async throws {
        try await RunnerVolumeListCommandService().run(
            account: options.account,
            path: options.path,
            name: name,
            repository: repository,
            sortBy: sortBy?.rawValue,
            sortOrder: sortOrder?.rawValue,
            page: pagination.page,
            pageSize: pagination.pageSize,
            json: options.json
        )
    }
}
