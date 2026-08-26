import Foundation

/// A command that can write its run report to a path chosen by the caller.
///
/// `TrackableCommand` reads `runReportPath` off the command it wraps, the same way it reads
/// `analyticsRequired` off `TrackableParsableCommand`.
public protocol RunReportingCommand {
    /// The path passed via `--run-report-path` / `TUIST_RUN_REPORT_PATH`, if any. Relative paths
    /// are resolved against the working directory.
    ///
    /// The written file is a `RunReport` encoded as JSON. Its format is documented for consumers in
    /// the "Run report" section of the Continuous Integration guide
    /// (`server/priv/docs/en/guides/integrations/continuous-integration.md`).
    var runReportPath: String? { get }
}
