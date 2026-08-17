import CoreData
import Foundation
import Pulse
import PulseLogHandler
import TuistLogging

public enum ApplicationLogStore {
    private static let maximumStoreSize: Int64 = 10_000_000
    private static let maximumAge: TimeInterval = 3 * 24 * 60 * 60
    private static let maximumSessionCount = 2
    private static let maximumMessageCount = 1000

    public static func bootstrap() {
        var configuration = LoggerStore.shared.configuration
        let existingEventHandler = configuration.willHandleEvent
        configuration.sizeLimit = maximumStoreSize
        configuration.maxAge = maximumAge
        configuration.willHandleEvent = { event in
            existingEventHandler(event).map(sanitized)
        }
        LoggerStore.shared.configuration = configuration

        LoggingSystem.bootstrap { label in
            var persistentLogHandler = PersistentLogHandler(label: label, store: .shared)
            persistentLogHandler.logLevel = .debug
            return MultiplexLogHandler([
                persistentLogHandler,
                StandardLogHandler(label: label, logLevel: .debug),
            ])
        }
    }

    public static func plainTextExport() async throws -> URL {
        let report = try await plainTextReport()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tuist-logs-\(fileNameDate(Date())).txt")
        try report.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    static func plainTextReport(
        store: LoggerStore = .shared,
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Unknown",
        appBuild: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
        operatingSystemVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        generatedAt: Date = Date()
    ) async throws -> String {
        let messages = try await recentMessages(store: store)
        let entries = messages.map { message in
            let metadata = message.metadata.isEmpty
                ? ""
                : " | metadata=" + message.metadata
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            return "\(format(message.date)) | \(message.level) | \(message.label) | \(message.text)"
                + metadata
                + " | source=\(message.file):\(message.line)"
        }

        return ([
            "Tuist application logs",
            "Generated: \(format(generatedAt))",
            "App version: \(appVersion) (\(appBuild))",
            "Operating system: \(operatingSystemVersion)",
            "Included sessions: up to \(maximumSessionCount) most recent launches",
            "Sensitive authentication values are redacted.",
            "",
            "Entries:",
        ] + (entries.isEmpty ? ["No application logs recorded."] : entries))
            .joined(separator: "\n")
    }

    static func sanitized(_ event: LoggerStore.Event) -> LoggerStore.Event {
        guard case let .messageStored(storedMessage) = event else { return event }
        var message = storedMessage
        message.message = redacted(message.message)
        message.metadata = message.metadata?.mapValues(redacted)
        if var metadata = message.metadata {
            for key in metadata.keys where isSensitiveMetadataKey(key) {
                metadata[key] = "[redacted]"
            }
            message.metadata = metadata
        }
        return .messageStored(message)
    }

    private static func recentMessages(store: LoggerStore) async throws -> [ReportMessage] {
        try await store.backgroundContext.perform {
            let sessionRequest = NSFetchRequest<LoggerSessionEntity>(entityName: "LoggerSessionEntity")
            sessionRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            sessionRequest.fetchLimit = maximumSessionCount
            let sessionIDs = try store.backgroundContext.fetch(sessionRequest).map(\.id)

            let messageRequest = NSFetchRequest<LoggerMessageEntity>(entityName: "LoggerMessageEntity")
            if !sessionIDs.isEmpty {
                messageRequest.predicate = NSPredicate(format: "session IN %@", sessionIDs)
            }
            messageRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            messageRequest.fetchLimit = maximumMessageCount

            return try store.backgroundContext.fetch(messageRequest).reversed().map { message in
                ReportMessage(
                    date: message.createdAt,
                    level: LoggerStore.Level(rawValue: message.level)?.name ?? "unknown",
                    label: message.label,
                    text: message.text,
                    metadata: message.metadata,
                    file: message.file,
                    line: message.line
                )
            }
        }
    }

    private static func redacted(_ value: String) -> String {
        [
            ("(?i)(bearer\\s+)[A-Za-z0-9._~+\\-/]+=*", "$1[redacted]"),
            (
                "(?i)\\b(access_token|refresh_token|id_token|authorization|password|api[_-]?key)=([^\\s&,]+)",
                "$1=[redacted]"
            ),
            ("\\beyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\b", "[redacted]"),
        ].reduce(value) { output, replacement in
            output.replacingOccurrences(
                of: replacement.0,
                with: replacement.1,
                options: .regularExpression
            )
        }
    }

    private static func isSensitiveMetadataKey(_ key: String) -> Bool {
        let key = key.lowercased()
        return ["authorization", "cookie", "token", "secret", "password", "api_key", "apikey"]
            .contains { key.contains($0) }
    }

    private static func format(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func fileNameDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter.string(from: date)
    }

    private struct ReportMessage: Sendable {
        let date: Date
        let level: String
        let label: String
        let text: String
        let metadata: [String: String]
        let file: String
        let line: Int32
    }
}
