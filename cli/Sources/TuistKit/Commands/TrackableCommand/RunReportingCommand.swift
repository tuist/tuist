import Foundation

/// A command that can write its run report to a path chosen by the caller.
///
/// `TrackableCommand` reads `runReportPath` off the command it wraps, the same way it reads
/// `analyticsRequired` off `TrackableParsableCommand`.
public protocol RunReportingCommand {
    /// The path passed via `--run-report-path` / `TUIST_RUN_REPORT_PATH`, if any. Relative paths
    /// are resolved against the working directory.
    var runReportPath: String? { get }
}
