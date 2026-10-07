/// Build settings that make code built with coverage bump its counters atomically.
///
/// Instrumented code bumps its coverage counters with plain increments, and tests running in
/// parallel in one process lose some of them. Most region counts are derived by subtracting one
/// counter from another, so a lost increment can turn into a negative count, into a line reported
/// covered that never ran, or into one reported uncovered that did. Atomic increments keep every
/// count exact.
///
/// The flags are keyed on `CLANG_COVERAGE_MAPPING`, which Xcode sets whenever it builds with
/// coverage, whether the scheme, the test plan or `-enableCodeCoverage` asked for it. Builds
/// without coverage resolve the reference to nothing, so their compiler invocations, and the
/// compilation cache keys derived from them, stay as they were.
enum AtomicCoverageCounters {
    private static let flags: [(setting: String, value: String)] = [
        ("OTHER_SWIFT_FLAGS", "-Xllvm -instrprof-atomic-counter-update-all"),
        ("OTHER_CFLAGS", "-fprofile-update=atomic"),
    ]

    /// `arguments` with the settings added. A setting the caller already overrides is extended
    /// rather than passed again, since xcodebuild keeps only the last value of a setting.
    static func adding(to arguments: [String]) -> [String] {
        var arguments = arguments
        for (setting, value) in flags {
            let variable = "TUIST_ATOMIC_COVERAGE_\(setting)"
            let reference = "$(\(variable)_$(CLANG_COVERAGE_MAPPING))"
            if let index = arguments.lastIndex(where: { $0.hasPrefix("\(setting)=") }) {
                arguments[index] += " \(reference)"
            } else {
                arguments.append("\(setting)=$(inherited) \(reference)")
            }
            arguments.append("\(variable)_YES=\(value)")
        }
        return arguments
    }
}
