import Foundation
import Logging

/// Package-scope logger. Rosalind emits diagnostic events at `.debug` and higher; when the embedder has
/// bootstrapped `LoggingSystem` (Tuist CLI does this at startup) the events flow into the session log file.
/// When nothing has bootstrapped, swift-log installs a no-op handler and these calls are effectively free.
let rosalindLogger = Logger(label: "dev.tuist.rosalind")

/// Emits a `.debug` event on entry, exit, and failure, tagged with the operation name and its wall-clock
/// duration. Use it to bracket any async step whose duration is worth knowing when reading a session log
/// after the fact.
func withTiming<T>(
    _ step: String,
    _ operation: () async throws -> T
) async throws -> T {
    let start = Date()
    rosalindLogger.debug("\(step): start")
    do {
        let result = try await operation()
        let elapsed = Date().timeIntervalSince(start)
        rosalindLogger.debug("\(step): done in \(formatDuration(elapsed))")
        return result
    } catch {
        let elapsed = Date().timeIntervalSince(start)
        rosalindLogger.debug("\(step): failed after \(formatDuration(elapsed)) with error: \(error)")
        throw error
    }
}

/// Emits a `.debug` heartbeat every `interval` seconds for as long as `operation` is running. When a step
/// hangs, this leaves a breadcrumb trail so the last line of a session log names the exact step and how
/// long it had been stuck. The heartbeat is cancelled the moment the operation returns or throws.
func withHeartbeat<T>(
    _ step: String,
    every interval: TimeInterval = 30,
    _ operation: () async throws -> T
) async throws -> T {
    let start = Date()
    let heartbeat = Task { @Sendable in
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            let elapsed = Date().timeIntervalSince(start)
            rosalindLogger.debug("\(step): still running after \(formatDuration(elapsed))")
        }
    }
    defer { heartbeat.cancel() }
    return try await operation()
}

private func formatDuration(_ seconds: TimeInterval) -> String {
    if seconds < 1 {
        return String(format: "%.0fms", seconds * 1000)
    }
    return String(format: "%.2fs", seconds)
}
