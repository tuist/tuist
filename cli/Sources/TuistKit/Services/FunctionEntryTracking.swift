import TuistCore

/// Build settings that build the code of the eligible targets (`TaskAttributionTargets`) with
/// function-entry tracking, which TestCoverageAttribution uses to attribute what Swift Testing tests
/// running in parallel in one process execute to each of them.
///
/// Passed to xcodebuild, like `AtomicCoverageCounters`, so the generated project and every hash
/// derived from it stay as they were. A setting can't name a target, so the flags are reached
/// through one variable per eligible target, named after `$(TARGET_NAME:c99extidentifier)`, and keyed
/// on `CLANG_COVERAGE_MAPPING`, which Xcode sets whenever it builds with coverage: other targets,
/// and builds without coverage, resolve the reference to nothing. `-sanitize=undefined` only lets the
/// Swift driver take `-sanitize-coverage`; it adds no checks to Swift code, and Xcode links no
/// sanitizer runtime for it.
enum FunctionEntryTracking {
    static let swiftFlags = "-sanitize=undefined -sanitize-coverage=func,trace-pc-guard,pc-table"
    static let variable = "TUIST_FUNCTION_TRACKING"

    /// `arguments` with the settings added for `targets`, identifiers as
    /// `TaskAttributionTargets.identifiers(graph:)` returns them. A setting the caller already
    /// overrides is extended rather than passed again, since xcodebuild keeps only its last value.
    static func adding(to arguments: [String], targets: Set<String>) -> [String] {
        guard !targets.isEmpty else { return arguments }
        var arguments = arguments
        let reference = "$(\(variable)_$(CLANG_COVERAGE_MAPPING)_$(TARGET_NAME:c99extidentifier))"
        if let index = arguments.lastIndex(where: { $0.hasPrefix("OTHER_SWIFT_FLAGS=") }) {
            arguments[index] += " \(reference)"
        } else {
            arguments.append("OTHER_SWIFT_FLAGS=$(inherited) \(reference)")
        }
        for target in targets.sorted() {
            arguments.append("\(variable)_YES_\(target)=\(swiftFlags)")
        }
        return arguments
    }
}
