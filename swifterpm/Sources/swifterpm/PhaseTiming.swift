import Foundation

/// Reports how long each resolution phase takes through `Environment.debugHandler`, so a slow
/// install can be attributed without a profiler.
enum PhaseTiming {
    static func measure<T>(_ phase: String, operation: () async throws -> T) async rethrows -> T {
        guard let debugHandler = Environment.debugHandler else { return try await operation() }
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await operation()
        debugHandler("\(phase) took \(format(clock.now - start))")
        return result
    }

    static func format(_ duration: Duration) -> String {
        let components = duration.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        return String(format: "%.3fs", seconds)
    }
}

extension SwifterPM {
    /// Routes SwifterPM's debug diagnostics, such as per-phase timings, to `debug`.
    public static func withDebugHandler<T>(
        _ debug: @escaping @Sendable (String) -> Void,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await Environment.$debugHandler.withValue(debug) { try await operation() }
    }
}
