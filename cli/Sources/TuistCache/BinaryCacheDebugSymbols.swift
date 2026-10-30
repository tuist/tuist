import TuistConfig

/// Whether the binaries a command reads and warms carry portable debug information.
///
/// With it on, a warm links Debug binaries with dSYMs and records each slice's source identities, and a
/// generation replaces a target only with an XCFramework whose identities match its sources. With it off, Debug
/// binaries keep their debug information in the warming machine's object files, no source identities are recorded,
/// and a generation uses the binaries without verifying them, so breakpoints in cached modules don't resolve to
/// their sources. Every key is put under a dimension when it's off, so the two kinds of binaries never stand in for
/// each other. The CLI resolves it from `Tuist.swift`'s `cacheOptions.debugSymbols`.
public enum BinaryCacheDebugSymbols: Equatable, Sendable {
    /// Binaries with dSYMs and source identities.
    case on
    /// Binaries without dSYMs or source identities.
    case off

    public init(config: Tuist) {
        self = config.project.generatedProject?.cacheOptions.debugSymbols == false ? .off : .on
    }
}
