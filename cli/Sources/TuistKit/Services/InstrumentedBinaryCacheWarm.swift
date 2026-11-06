import Path
import TuistCore
import XcodeGraph
import XCResultParser

/// The build settings of a `tuist cache` warm with coverage on, which builds the repository's own targets with
/// coverage counters so a `tuist test` run that collects coverage measures the cached code it links.
///
/// The settings are passed on the xcodebuild command line, where they beat every project and target
/// setting, and resolve through `InstrumentedBinaryCacheWarmGraphMapper`'s marker, which only the
/// repository's frameworks and libraries carry: external packages in the same build keep compiling
/// plain, since coverage is never kept for their code and their binaries are stored under the plain key.
///
/// `CLANG_COVERAGE_MAPPING` is what Xcode sets when a test action gathers coverage; it makes the
/// compilers emit the coverage mapping and link the profile runtime. The counters are atomic, as
/// `tuist test` builds them (`AtomicCoverageCounters`). The checkout's root is recorded as
/// `/TUIST_SOURCE_ROOT`, the same on every machine, so the export of a run on another machine ties the
/// cached code's files to the repository like the checkout's own; the compiler records the path spelling
/// the build used, so every spelling of the root is mapped.
enum InstrumentedBinaryCacheWarm {
    static let markerSetting = "TUIST_BINARY_CACHE_COVERAGE"
    static let sourceRootPlaceholder = XcodeCoverageManifest.sourceRootPlaceholder

    /// Every spelling of the checkout root the compiler may record: the given ones, and on macOS each
    /// one's twin with or without the `/private` prefix, since `/tmp`, `/var` and `/etc` are symbolic
    /// links into `/private` and Xcode records whichever spelling it was handed, which is not always the
    /// one the command line used.
    static func sourceRoots(_ spellings: [String]) -> [String] {
        var roots: [String] = []
        for spelling in spellings {
            roots.append(spelling)
            if spelling.hasPrefix("/private/") {
                roots.append(String(spelling.dropFirst("/private".count)))
            } else if ["/tmp", "/var", "/etc"].contains(where: { spelling == $0 || spelling.hasPrefix($0 + "/") }) {
                roots.append("/private" + spelling)
            }
        }
        return roots.reduce(into: []) { unique, root in
            if !unique.contains(root) { unique.append(root) }
        }
    }

    /// `KEY=VALUE` settings for xcodebuild's command line.
    static func buildSettings(sourceRoots: [String]) -> [String] {
        let marker = "$(\(markerSetting))"
        let swiftFlags = [AtomicCoverageCounters.swiftFlags] + sourceRoots.map {
            "-coverage-prefix-map \(SettingValue.quoted("\($0)=\(sourceRootPlaceholder)"))"
        }
        let cFlags = [AtomicCoverageCounters.cFlags] + sourceRoots.map {
            SettingValue.quoted("-fcoverage-prefix-map=\($0)=\(sourceRootPlaceholder)")
        }
        return [
            "CLANG_COVERAGE_MAPPING=$(TUIST_BINARY_CACHE_COVERAGE_MAPPING_\(marker))",
            "TUIST_BINARY_CACHE_COVERAGE_MAPPING_=NO",
            "TUIST_BINARY_CACHE_COVERAGE_MAPPING_YES=YES",
            "OTHER_SWIFT_FLAGS=$(inherited) $(TUIST_BINARY_CACHE_COVERAGE_SWIFT_FLAGS_\(marker))",
            "TUIST_BINARY_CACHE_COVERAGE_SWIFT_FLAGS_YES=\(swiftFlags.joined(separator: " "))",
            "OTHER_CFLAGS=$(inherited) $(TUIST_BINARY_CACHE_COVERAGE_CFLAGS_\(marker))",
            // C++ inherits the C flags through `OTHER_CPLUSPLUSFLAGS`'s default only; a target that
            // sets it would otherwise compile with coverage but without the mapping and the atomic counters.
            "OTHER_CPLUSPLUSFLAGS=$(inherited) $(TUIST_BINARY_CACHE_COVERAGE_CFLAGS_\(marker))",
            "TUIST_BINARY_CACHE_COVERAGE_CFLAGS_YES=\(cFlags.joined(separator: " "))",
        ]
    }
}
