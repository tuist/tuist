/// The variant of the binary cache a command reads and warms for the repository-owned targets.
///
/// A target served from the cache is a prebuilt binary, and a run measures its code only when that
/// binary was built with coverage. Repository-owned targets of a debug configuration are keyed on this
/// dimension when it's on, so every command and machine that resolves it the same way shares one
/// instrumented variant. The CLI resolves it from `TUIST_COVERAGE_ENABLED`, then `Tuist.swift`'s
/// `coverage.enabled`; whether a run collects coverage is left to its schemes, test plans and
/// `-enableCodeCoverage`.
public enum BinaryCacheCoverage: Equatable, Sendable {
    /// The plain binaries.
    case off
    /// The binaries built with coverage counters.
    case on
}
