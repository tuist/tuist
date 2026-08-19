#if !os(Linux)
    import FileSystem
    import Foundation
    import Path

    public protocol ApplicationLogStoring: Sendable {
        @MainActor func bootstrap() async
        func plainTextExport() async throws -> URL
    }

    public final class ApplicationLogStore: ApplicationLogStoring, Sendable {
        @TaskLocal public static var current: any ApplicationLogStoring = ApplicationLogStore()

        private static let maximumAge: TimeInterval = 3 * 24 * 60 * 60
        private static let maximumSessionCount = 2
        private static let maximumSessionSize: UInt64 = 5_000_000
        @MainActor private static var hasBootstrapped = false

        private let fileSystem: FileSysteming
        private let logsDirectory: AbsolutePath
        @MainActor private var activeLogHandler: SimpleFileLogHandler?

        public convenience init() {
            self.init(logsDirectory: Self.defaultLogsDirectory)
        }

        init(
            logsDirectory: AbsolutePath,
            fileSystem: FileSysteming = FileSystem()
        ) {
            self.logsDirectory = logsDirectory
            self.fileSystem = fileSystem
        }

        @MainActor
        public func bootstrap() async {
            guard !Self.hasBootstrapped else { return }
            Self.hasBootstrapped = true

            do {
                var fileLogHandler = try await makeFileLogHandler()
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
            let exportPath = Self.temporaryDirectory
                .appending(component: "tuist-logs-\(Self.fileNameDate(generatedAt))-\(UUID().uuidString).txt")
            try await fileSystem.writeText(report, at: exportPath)
            return URL(fileURLWithPath: exportPath.pathString)
        }

        func plainTextReport(
            appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "Unknown",
            appBuild: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            operatingSystemVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
            generatedAt: Date = Date()
        ) async throws -> String {
            let activeLogHandler = await MainActor.run { self.activeLogHandler }
            var sessions: [String] = []
            for session in try await recentSessionFiles(generatedAt: generatedAt) {
                let contents = if activeLogHandler?.fileURL.path == session.path.pathString {
                    try activeLogHandler?.contents() ?? ""
                } else {
                    try await fileSystem.readTextFile(at: session.path)
                }
                let trimmedContents = contents.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedContents.isEmpty else { continue }
                sessions.append("Launch: \(session.path.basename)\n\(trimmedContents)")
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
        func makeFileLogHandler(generatedAt: Date = Date()) async throws -> SimpleFileLogHandler {
            if try await !fileSystem.exists(logsDirectory) {
                try await fileSystem.makeDirectory(at: logsDirectory)
            }

            var logsDirectoryURL = URL(fileURLWithPath: logsDirectory.pathString)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? logsDirectoryURL.setResourceValues(resourceValues)

            let sessionPath = logsDirectory.appending(
                component: "session-\(Self.fileNameDate(generatedAt))-\(UUID().uuidString).txt"
            )
            let handler = try SimpleFileLogHandler(
                label: "dev.tuist.app",
                fileURL: URL(fileURLWithPath: sessionPath.pathString),
                maximumFileSize: Self.maximumSessionSize,
                lineTransformer: Self.redacted,
                shouldLog: Self.shouldStore
            )
            try await removeExpiredSessions(generatedAt: generatedAt)
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

        private func recentSessionFiles(generatedAt: Date) async throws -> [SessionFile] {
            let cutoffDate = generatedAt.addingTimeInterval(-Self.maximumAge)
            return try await sessionFiles()
                .filter { $0.lastModificationDate >= cutoffDate }
                .sorted { $0.lastModificationDate > $1.lastModificationDate }
                .prefix(Self.maximumSessionCount)
                .map { $0 }
        }

        private func removeExpiredSessions(generatedAt: Date) async throws {
            let cutoffDate = generatedAt.addingTimeInterval(-Self.maximumAge)
            let sessionFiles = try await sessionFiles()
                .sorted { $0.lastModificationDate > $1.lastModificationDate }

            for (index, session) in sessionFiles.enumerated()
                where index >= Self.maximumSessionCount || session.lastModificationDate < cutoffDate
            {
                try? await fileSystem.remove(session.path)
            }
        }

        private func sessionFiles() async throws -> [SessionFile] {
            guard try await fileSystem.exists(logsDirectory) else { return [] }

            var sessions: [SessionFile] = []
            for path in try await fileSystem.contentsOfDirectory(logsDirectory)
                where path.basename.hasPrefix("session-") && path.extension == "txt"
            {
                guard let metadata = try await fileSystem.fileMetadata(at: path) else { continue }
                sessions.append(SessionFile(path: path, lastModificationDate: metadata.lastModificationDate))
            }
            return sessions
        }

        private static var defaultLogsDirectory: AbsolutePath {
            guard let homeDirectory = try? AbsolutePath(validating: NSHomeDirectory()) else {
                fatalError("The home directory must be an absolute path.")
            }
            return homeDirectory
                .appending(component: "Library")
                .appending(component: "Application Support")
                .appending(component: Bundle.main.bundleIdentifier ?? "dev.tuist.app")
                .appending(component: "Logs")
        }

        private static var temporaryDirectory: AbsolutePath {
            guard let temporaryDirectory = try? AbsolutePath(validating: NSTemporaryDirectory()) else {
                fatalError("The temporary directory must be an absolute path.")
            }
            return temporaryDirectory
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

        private struct SessionFile {
            let path: AbsolutePath
            let lastModificationDate: Date
        }
    }
#endif
