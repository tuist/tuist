import ArgumentParser
import Foundation

/// How `--stress-new-tests` behaves once the gate finds a newly added test that is flaky.
/// Off is not passing the option at all, so there is no default mode.
public enum StressNewTestsMode: String, Sendable, CaseIterable, ExpressibleByArgument {
    /// Warns about the disagreement and exits on the first pass's own result.
    case report
    /// Fails the run on a disagreement, with the same exit code as a failed test run.
    case enforce
}
