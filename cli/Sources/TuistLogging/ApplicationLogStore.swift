#if os(iOS) || os(macOS)
    import Foundation

    public protocol ApplicationLogStoring: Sendable {
        @MainActor func bootstrap()
        func plainTextExport() async throws -> URL
    }

    public final class ApplicationLogStore: ApplicationLogStoring, Sendable {
        @TaskLocal public static var current: any ApplicationLogStoring = ApplicationLogStore()

        private static let maximumAge: TimeInterval = 3 * 24 * 60 * 60
        private static let maximumSessionCount = 2
        private static let maximumSessionSize: UInt64 = 5_000_000
        @MainActor private static var hasBootstrapped = false

        private let logsDirectory: URL
        @MainActor private var activeLogHandler: SimpleFileLogHandler?

        public convenience init() {
            self.init(logsDirectory: Self.defaultLogsDirectory)
        }

        init(logsDirectory: URL) {
            self.logsDirectory = logsDirectory
        }

        @MainActor
        public func bootstrap() {
            guard !Self.hasBootstrapped else { return }
            Self.hasBootstrapped = true

            do {
                var fileLogHandler = try makeFileLogHandler()
                fileLogHandler.logLevel = .debug
                activeLogHandler = fileLogHandler
                LoggingSystem.bootstrap { label in
                    MultiplexLogHandler([
                        fileLogHandler,
                        StandardLogHandler(label: label, logLevel: .debug),
                    ])
                }
            } catch {
                LoggingSystem.bootstrap { label in
                    StandardLogHandler(label: label, logLevel: .debug)
                }
            }
        }

        public func plainTextExport() async throws -> URL {
            let generatedAt = Date()
            let report = try await plainTextReport(generatedAt: generatedAt)
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("tuist-logs-\(Self.fileNameDate(generatedAt))-\(UUID().uuidString).txt")
            try report.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        }

        func plainTextReport(
            appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "Unknown",
            appBuild: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            operatingSystemVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
            generatedAt: Date = Date()
        ) async throws -> String {
            let activeLogHandler = await MainActor.run { self.activeLogHandler }
            let sessions = try recentSessionFiles(generatedAt: generatedAt).compactMap { fileURL -> String? in
                let contents = if activeLogHandler?.fileURL == fileURL {
                    try activeLogHandler?.contents() ?? ""
                } else {
                    try String(contentsOf: fileURL, encoding: .utf8)
                }
                let trimmedContents = contents.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedContents.isEmpty else { return nil }
                return "Launch: \(fileURL.lastPathComponent)\n\(trimmedContents)"
            }

            return ([
                "Tuist application logs",
                "Generated: \(Self.format(generatedAt))",
                "App version: \(appVersion) (\(appBuild))",
                "Operating system: \(operatingSystemVersion)",
                "Included launches: \(sessions.count) of up to \(Self.maximumSessionCount) recent launches",
                "Sensitive authentication values are redacted before logs are stored.",
                "",
                "Entries:",
            ] + (sessions.isEmpty ? ["No application logs recorded."] : sessions))
                .joined(separator: "\n")
        }

        @MainActor
        func makeFileLogHandler(generatedAt: Date = Date()) throws -> SimpleFileLogHandler {
            try FileManager.default.createDirectory(
                at: logsDirectory,
                withIntermediateDirectories: true
            )
            var logsDirectory = logsDirectory
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? logsDirectory.setResourceValues(resourceValues)

            let fileURL = logsDirectory.appendingPathComponent(
                "session-\(Self.fileNameDate(generatedAt))-\(UUID().uuidString).txt"
            )
            let handler = try SimpleFileLogHandler(
                label: "dev.tuist.app",
                fileURL: fileURL,
                maximumFileSize: Self.maximumSessionSize,
                lineTransformer: Self.redacted,
                shouldLog: Self.shouldStore
            )
            try removeExpiredSessions(generatedAt: generatedAt)
            return handler
        }

        static func redacted(_ value: String) -> String {
            [
                ("(?i)(bearer\\s+)[A-Za-z0-9._~+\\-/]+=*", "$1[redacted]"),
                (
                    "(?i)\\b(access_token|refresh_token|id_token|authorization|password|api[_-]?key)=([^\\s&,]+)",
                    "$1=[redacted]"
                ),
                (
                    "(?i)([\"']?[A-Za-z0-9_.-]*(?:authorization|cookie|token|secret|password|api[_-]?key)[A-Za-z0-9_.-]*[\"']?\\s*:\\s*[\"']?)([^\"',\\]\\s&]+)",
                    "$1[redacted]"
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

        private static func shouldStore(_: Logger.Level, _ message: Logger.Message, _: String) -> Bool {
            !message.description.hasPrefix("Sending HTTP request to ")
                && !message.description.hasPrefix("Received HTTP response from ")
        }

        private func recentSessionFiles(generatedAt: Date) throws -> [URL] {
            let cutoffDate = generatedAt.addingTimeInterval(-Self.maximumAge)
            return try sessionFiles()
                .filter { Self.modificationDate(for: $0) >= cutoffDate }
                .sorted { Self.modificationDate(for: $0) > Self.modificationDate(for: $1) }
                .prefix(Self.maximumSessionCount)
                .map { $0 }
        }

        private func removeExpiredSessions(generatedAt: Date) throws {
            let cutoffDate = generatedAt.addingTimeInterval(-Self.maximumAge)
            let sessionFiles = try sessionFiles()
                .sorted { Self.modificationDate(for: $0) > Self.modificationDate(for: $1) }

            for (index, fileURL) in sessionFiles.enumerated()
                where index >= Self.maximumSessionCount || Self.modificationDate(for: fileURL) < cutoffDate
            {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }

        private func sessionFiles() throws -> [URL] {
            guard FileManager.default.fileExists(atPath: logsDirectory.path) else { return [] }
            return try FileManager.default.contentsOfDirectory(
                at: logsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.lastPathComponent.hasPrefix("session-") && $0.pathExtension == "txt" }
        }

        private static var defaultLogsDirectory: URL {
            let applicationSupportDirectory = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            return applicationSupportDirectory
                .appendingPathComponent(Bundle.main.bundleIdentifier ?? "dev.tuist.app", isDirectory: true)
                .appendingPathComponent("Logs", isDirectory: true)
        }

        private static func modificationDate(for fileURL: URL) -> Date {
            (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }

        private static func format(_ date: Date) -> String {
            ISO8601DateFormatter().string(from: date)
        }

        private static func fileNameDate(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
            return formatter.string(from: date)
        }
    }
#endif
