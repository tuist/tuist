import ArgumentParser
import Foundation
import TuistNooraExtension

enum SandboxStatus: String, ExpressibleByArgument, CaseIterable {
    case active, idle, starting, resuming, paused, archived, failed
}

enum SandboxSort: String, ExpressibleByArgument, CaseIterable {
    case created
    case lastActive = "last_active"
    case name
}

enum SandboxSortOrder: String, ExpressibleByArgument, CaseIterable {
    case asc, desc
}

public struct SandboxListCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List sandboxes, newest first, with their status and shape."
    )

    @OptionGroup var options: SandboxOptions

    @Option(name: .long, help: "Text the sandbox ID, Amp Orb ID or Anthropic session ID contains.")
    var search: String?

    @Option(name: .long, help: "Only sandboxes with this status.")
    var status: SandboxStatus?

    @Option(name: .long, help: "Only sandboxes with this many vCPUs.")
    var vcpus: Int?

    @Option(name: .long)
    var sortBy: SandboxSort?

    @Option(name: .long)
    var sortOrder: SandboxSortOrder?

    @Option(name: .long, help: "Page number, starting at 1.")
    var page = 1

    @Option(name: .long, help: "Results per page (1–100).")
    var pageSize = 20

    public var jsonThroughNoora: Bool { true }

    public func validate() throws {
        guard (1 ... 100_000).contains(page), (1 ... 100).contains(pageSize) else {
            throw ValidationError("Page must be 1–100000 and page size must be 1–100.")
        }
        if let search, !(1 ... 200).contains(search.count) {
            throw ValidationError("Search must be 1–200 characters.")
        }
    }

    public func run() async throws {
        try await SandboxCommandService().list(
            options: options.values,
            search: search,
            status: status?.rawValue,
            vcpus: vcpus,
            sortBy: sortBy?.rawValue,
            sortOrder: sortOrder?.rawValue,
            page: page,
            pageSize: pageSize
        )
    }
}
