import ArgumentParser
import Foundation
import TuistNooraExtension

public struct RunnerVolumeAnalyticsCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "analytics",
        abstract: "Show storage, hit rate, job runs and trends. Defaults to the last seven days."
    )

    @OptionGroup var options: RunnerVolumeOptions

    @Option(name: .long, help: "Volume UUID. Omit for account-wide analytics.")
    var volume: String?

    @Option(name: .long, help: "Inclusive range start as an ISO 8601 timestamp.")
    var start: String?

    @Option(name: .long, help: "Inclusive range end as an ISO 8601 timestamp.")
    var end: String?

    public var jsonThroughNoora: Bool { true }

    public func validate() throws {
        if let volume { try RunnerVolumeValidation.validateID(volume) }
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

    public func run() async throws {
        let (startDate, endDate) = try dateRange()
        try await RunnerVolumeAnalyticsCommandService().run(
            volumeID: volume,
            account: options.account,
            path: options.path,
            start: startDate,
            end: endDate,
            json: options.json
        )
    }
}
