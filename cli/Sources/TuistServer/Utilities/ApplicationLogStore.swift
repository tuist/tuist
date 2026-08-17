import Foundation

public enum ApplicationLogLevel: String, Sendable {
    case debug
    case info
    case notice
    case warning
    case error
}

public actor ApplicationLogStore {
    public static let shared = ApplicationLogStore()

    private struct Entry: Sendable {
        let date: Date
        let level: ApplicationLogLevel
        let category: String
        let message: String
    }

    private let maximumEntryCount: Int
    private var entries: [Entry] = []

    public init(maximumEntryCount: Int = 200) {
        precondition(maximumEntryCount > 0)
        self.maximumEntryCount = maximumEntryCount
    }

    @discardableResult
    public nonisolated func record(
        level: ApplicationLogLevel,
        category: String,
        message: String,
        at date: Date = Date()
    ) -> Task<Void, Never> {
        Task {
            await append(
                Entry(
                    date: date,
                    level: level,
                    category: category,
                    message: message
                )
            )
        }
    }

    public func report(
        appVersion: String,
        appBuild: String,
        operatingSystemVersion: String,
        generatedAt: Date = Date()
    ) -> String {
        let lines = entries.map { entry in
            "\(Self.format(entry.date)) | \(entry.level.rawValue) | \(entry.category) | \(entry.message)"
        }

        return ([
            "Tuist application logs",
            "Generated: \(Self.format(generatedAt))",
            "App version: \(appVersion) (\(appBuild))",
            "Operating system: \(operatingSystemVersion)",
            "",
            "Authentication credential values are not recorded.",
            "",
            "Entries:",
        ] + (lines.isEmpty ? ["No application logs recorded."] : lines))
            .joined(separator: "\n")
    }

    public func currentProcessReport(generatedAt: Date = Date()) -> String {
        report(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            generatedAt: generatedAt
        )
    }

    private func append(_ entry: Entry) {
        entries.append(entry)
        if entries.count > maximumEntryCount {
            entries.removeFirst(entries.count - maximumEntryCount)
        }
    }

    private static func format(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
