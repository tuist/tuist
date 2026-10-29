import Path
import TuistCore
import XcodeGraph

/// Whether the binaries a run took from the binary cache carry coverage counters.
///
/// A cached target is a prebuilt binary, and a run that collects coverage measures its code only
/// when the binary was built with coverage. The server judges a commit's coverage per target from
/// what each run reports (`xcode_targets.binary_cache_instrumented`): a plain hit is a gap, an
/// instrumented one counts as measured, and a run is no source of coverage for a test target that
/// linked a plain one. The flag is read off the binaries themselves, so it holds whatever key the
/// binary was cached under.
enum CoverageInstrumentation {
    /// `items` with every hit of the binary cache told whether its binary was built with coverage.
    /// `graph` still holds the replaced targets; `generatedGraph` links their xcframeworks instead.
    /// A hit whose xcframework the graph doesn't link, or a miss, is left as it is.
    static func annotate(
        _ items: [AbsolutePath: [String: CacheItem]],
        graph: Graph,
        generatedGraph: Graph,
        isInstrumented: (String) -> Bool = CoverageMapping.isInstrumented(path:)
    ) -> [AbsolutePath: [String: CacheItem]] {
        let xcframeworks = CoverageBuildTargets.xcframeworks(in: generatedGraph)
        return Dictionary(uniqueKeysWithValues: items.map { path, itemsByName in
            (path, itemsByName.mapValues { item in
                guard item.source != .miss, item.cacheCategory == .binaries,
                      let target = graph.projects[path]?.targets[item.name]
                else { return item }
                let binaries = CoverageBuildTargets.binaries(of: xcframeworks[target.productName])
                guard !binaries.isEmpty else { return item }
                return item.with(instrumented: binaries.contains { isInstrumented($0.path) })
            })
        })
    }
}
