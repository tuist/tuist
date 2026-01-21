import Foundation
import Path

/// An actor that manages HAR recording and persistence.
public actor HARRecorder {
    /// The current HAR recorder instance for the session.
    @TaskLocal public static var current: HARRecorder?

    /// Headers that should be redacted for security reasons.
    public static let sensitiveHeaders: Set<String> = [
        "authorization",
        "cookie",
        "set-cookie",
        "x-api-key",
        "x-auth-token",
        "x-access-token",
        "proxy-authorization",
        "www-authenticate",
        "x-amz-security-token",
        "x-amz-credential",
    ]

    private var log: HAR.Log
    private let filePath: AbsolutePath?

    /// Creates a new HAR recorder.
    /// - Parameters:
    ///   - filePath: The path where the HAR file will be saved. If nil, entries are only stored in memory.
    ///   - creatorName: The name of the application creating the HAR file.
    ///   - creatorVersion: The version of the application.
    public init(
        filePath: AbsolutePath? = nil,
        creatorName: String = "Tuist",
        creatorVersion: String = Constants.version
    ) {
        self.filePath = filePath
        log = HAR.Log(
            creator: HAR.Creator(name: creatorName, version: creatorVersion)
        )
    }

    /// Records a new entry to the HAR log.
    /// - Parameter entry: The entry to record.
    public func record(_ entry: HAR.Entry) async {
        log.entries.append(entry)
        await persist()
    }

    /// Returns the current HAR log.
    public func getLog() async -> HAR.Log {
        log
    }

    /// Returns all recorded entries.
    public func getEntries() async -> [HAR.Entry] {
        log.entries
    }

    /// Filters sensitive headers from a list of headers.
    /// - Parameter headers: The headers to filter.
    /// - Returns: Headers with sensitive values redacted.
    public static func filterSensitiveHeaders(_ headers: [HAR.Header]) -> [HAR.Header] {
        headers.map { header in
            if sensitiveHeaders.contains(header.name.lowercased()) {
                return HAR.Header(name: header.name, value: "[REDACTED]", comment: header.comment)
            }
            return header
        }
    }

    /// Persists the current HAR log to disk if a file path was provided.
    private func persist() async {
        guard let filePath else { return }
        do {
            let data = try HAR.encode(log)
            try data.write(to: filePath.url, options: .atomic)
        } catch {
            #if os(macOS)
                Logger.current.debug("Failed to persist HAR file: \(error)")
            #endif
        }
    }
}
