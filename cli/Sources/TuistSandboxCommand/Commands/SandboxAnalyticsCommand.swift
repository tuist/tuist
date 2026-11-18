import ArgumentParser
import Foundation
import TuistNooraExtension

public struct SandboxAnalyticsCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "analytics",
        abstract: "Show vCPU-hours, sandboxes created, durations and peak usage against limits. Defaults to the last 30 days."
    )

    @OptionGroup var options: SandboxOptions

    @Option(name: .long, help: "Range start as an ISO 8601 timestamp.")
    var start: String?

    @Option(name: .long, help: "Range end as an ISO 8601 timestamp. Defaults to now.")
    var end: String?

    public var jsonThroughNoora: Bool { true }

    public func validate() throws {
        _ = try dateRange()
    }

    func dateRange() throws -> (Date?, Date?) {
        let first = try Self.date(start)
        let last = try Self.date(end)
        let finish = last ?? Date()
        let begin = first ?? finish.addingTimeInterval(-30 * 86400)
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
        let (start, end) = try dateRange()
        try await SandboxCommandService().analytics(options: options.values, start: start, end: end)
    }
}
