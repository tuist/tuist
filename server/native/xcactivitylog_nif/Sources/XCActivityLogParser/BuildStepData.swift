import Foundation

public struct BuildStepData: Encodable, Sendable {
    public let event_id: Int
    public let title: String
    public let target: String
    public let project: String
    public let category: String
    public let start_ms: Double
    public let duration_ms: Double
    public let status: String
    public let log: String
    public let log_truncated: Bool

    /// Incremental logs retain steps from earlier builds. Only intervals fully
    /// within this recording describe work performed by this invocation.
    static func interval(start: Double, end: Double, buildStart: Double, buildEnd: Double) -> (Double, Double)? {
        guard start.isFinite, end.isFinite, buildStart.isFinite, buildEnd.isFinite,
              start >= buildStart, end <= buildEnd, end > start
        else { return nil }
        return ((start - buildStart) * 1000, (end - start) * 1000)
    }
}
