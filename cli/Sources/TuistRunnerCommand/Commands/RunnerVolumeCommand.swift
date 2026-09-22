import ArgumentParser
import Foundation
import TuistNooraExtension

public struct RunnerVolumeCommand: AsyncParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "volume",
            abstract: "Inspect and clear persistent runner cache volumes.",
            subcommands: [
                RunnerVolumeListCommand.self, RunnerVolumeShowCommand.self,
                RunnerVolumeJobsCommand.self, RunnerVolumeAnalyticsCommand.self,
                RunnerVolumeForJobCommand.self, RunnerVolumeClearCommand.self,
            ]
        )
    }
}

struct RunnerVolumeOptions: ParsableArguments {
    @Option(name: .long, help: "Account handle. Defaults to the account in the project's full handle.")
    var account: String?
    @Option(name: .shortAndLong, help: "Project directory.", completion: .directory)
    var path: String?
    @Flag(help: "Return response data and pagination as JSON. Unknown optional values are omitted.")
    var json = false
}

struct RunnerVolumePagination: ParsableArguments {
    @Option(name: .long, help: "Page number, starting at 1.")
    var page = 1
    @Option(name: .long, help: "Results per page (1–100).")
    var pageSize = 20

    func validate() throws {
        guard (1 ... 100_000).contains(page), (1 ... 100).contains(pageSize) else {
            throw ValidationError("Page must be 1–100000 and page size must be 1–100.")
        }
    }
}

enum RunnerVolumeSort: String, ExpressibleByArgument, CaseIterable {
    case volume, repository
    case usedSpace = "used_space"
    case capacity
    case lastUsed = "last_used"
}

enum RunnerVolumeSortOrder: String, ExpressibleByArgument, CaseIterable {
    case asc, desc
}

struct RunnerVolumeListCommand: AsyncParsableCommand, NooraReadyCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List, search and sort volumes.")
    @OptionGroup var options: RunnerVolumeOptions
    @OptionGroup var pagination: RunnerVolumePagination
    @Option(name: .long) var search: String?
    @Option(name: .long) var sortBy: RunnerVolumeSort?
    @Option(name: .long) var sortOrder: RunnerVolumeSortOrder?
    var jsonThroughNoora: Bool { true }

    func run() async throws {
        let service = try await RunnerVolumeService.resolve(options)
        try await service.list(search: search, sort: sortBy, order: sortOrder, pagination: pagination)
    }
}

struct RunnerVolumeShowCommand: AsyncParsableCommand, NooraReadyCommand {
    static let configuration = CommandConfiguration(commandName: "show", abstract: "Show volume details.")
    @Argument(help: "Volume UUID.") var volumeID: String
    @OptionGroup var options: RunnerVolumeOptions
    var jsonThroughNoora: Bool { true }
    func validate() throws { try validateVolumeID(volumeID) }
    func run() async throws { try await RunnerVolumeService.resolve(options).show(volumeID) }
}

struct RunnerVolumeJobsCommand: AsyncParsableCommand, NooraReadyCommand {
    static let configuration = CommandConfiguration(commandName: "jobs", abstract: "Show jobs that used a volume.")
    @Argument(help: "Volume UUID.") var volumeID: String
    @OptionGroup var options: RunnerVolumeOptions
    @OptionGroup var pagination: RunnerVolumePagination
    var jsonThroughNoora: Bool { true }
    func validate() throws { try validateVolumeID(volumeID) }
    func run() async throws { try await RunnerVolumeService.resolve(options).jobs(volumeID, pagination: pagination) }
}

struct RunnerVolumeForJobCommand: AsyncParsableCommand, NooraReadyCommand {
    static let configuration = CommandConfiguration(commandName: "for-job", abstract: "Show volumes mounted by a job.")
    @Argument(help: "Tuist workflow job identifier.") var jobID: Int
    @OptionGroup var options: RunnerVolumeOptions
    var jsonThroughNoora: Bool { true }
    func validate() throws {
        guard jobID > 0 else { throw ValidationError("Job ID must be positive.") }
    }

    func run() async throws { try await RunnerVolumeService.resolve(options).forJob(jobID) }
}

struct RunnerVolumeAnalyticsCommand: AsyncParsableCommand, NooraReadyCommand {
    static let configuration = CommandConfiguration(
        commandName: "analytics",
        abstract: "Show storage, hit rate, job runs and trends. Defaults to the last seven days."
    )
    @OptionGroup var options: RunnerVolumeOptions
    @Option(name: .long, help: "Volume UUID. Omit for account-wide analytics.") var volume: String?
    @Option(name: .long, help: "Inclusive range start as an ISO 8601 timestamp.") var start: String?
    @Option(name: .long, help: "Inclusive range end as an ISO 8601 timestamp.") var end: String?
    var jsonThroughNoora: Bool { true }
    func validate() throws {
        if let volume { try validateVolumeID(volume) }
        _ = try dateRange()
    }

    func dateRange() throws -> (Date?, Date?) {
        let first = try Self.date(start)
        let last = try Self.date(end)
        let finish = last ?? Date()
        let begin = first ?? finish.addingTimeInterval(-7 * 86400)
        guard finish > begin, finish.timeIntervalSince(begin) <= 90 * 86400, finish <= Date() else {
            throw ValidationError("Use an ordered range of at most 90 days ending no later than now.")
        }
        return (first, last)
    }

    private static func date(_ value: String?) throws -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        guard let date = formatter.date(from: value) else { throw ValidationError("Invalid ISO 8601 timestamp: \(value)") }
        return date
    }

    func run() async throws {
        let (startDate, endDate) = try dateRange()
        try await RunnerVolumeService.resolve(options).analytics(volume, start: startDate, end: endDate)
    }
}

struct RunnerVolumeClearCommand: AsyncParsableCommand, NooraReadyCommand {
    static let configuration = CommandConfiguration(
        commandName: "clear",
        abstract: "Clear saved contents. Running jobs keep their copies but cannot save them."
    )
    @Argument(help: "Volume UUID.") var volumeID: String
    @OptionGroup var options: RunnerVolumeOptions
    @Flag(name: .long, help: "Confirm clearing the saved contents. This cannot be undone.") var yes = false
    var jsonThroughNoora: Bool { true }
    func validate() throws {
        try validateVolumeID(volumeID)
        guard yes else { throw ValidationError("Pass --yes to confirm clearing the volume's saved contents.") }
    }

    func run() async throws { try await RunnerVolumeService.resolve(options).clear(volumeID) }
}

private func validateVolumeID(_ value: String) throws {
    guard UUID(uuidString: value) != nil else { throw ValidationError("Volume ID must be a UUID.") }
}
