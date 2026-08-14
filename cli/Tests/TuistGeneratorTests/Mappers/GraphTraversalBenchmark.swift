import Foundation
import Path
import Testing
import XcodeGraph
@testable import TuistCore
@testable import TuistGenerator

/// Measures the cost of the graph work that binary-cache generation performs, on a source graph and on the same
/// graph after binary substitution.
///
/// The two phases measured are the ones that dominate a warm `tuist generate` on a large project:
/// `FrameworkSearchPathsGraphMapper`, which calls `searchablePathDependencies` for every target in the graph, and
/// `allProjectDependencies`, which project file element generation calls once per project.
///
/// Skipped unless `TUIST_GRAPH_BENCHMARK` is set, because it is a measurement rather than an assertion.
///
/// `xcodebuild` does not forward the shell environment into a hostless xctest bundle, so set the variable in the
/// scheme's test action, or flip `isEnabled` while measuring locally:
///
///     tuist generate tuist ProjectDescription TuistGeneratorTests --no-open
///     xcodebuild test -workspace Tuist.xcworkspace -scheme TuistUnitTests \
///       -only-testing TuistGeneratorTests/GraphTraversalBenchmark \
///       -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
struct GraphTraversalBenchmark {
    private static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["TUIST_GRAPH_BENCHMARK"] != nil
    }

    private struct Shape {
        let projectCount: Int
        let targetsPerProject: Int
        let layerCount: Int
        /// Number of dependencies each target draws from the layer beneath it.
        let fanOut: Int
    }

    @Test(.enabled(if: GraphTraversalBenchmark.isEnabled, "Benchmark: set TUIST_GRAPH_BENCHMARK to run"))
    func frameworkSearchPathsAndProjectDependencies() async throws {
        let shape = Shape(projectCount: 100, targetsPerProject: 8, layerCount: 5, fanOut: 6)

        let (sourceGraph, layerByTarget) = makeGraph(shape: shape)
        // The top two layers stay as source targets, mirroring a focused generation where the targets being worked
        // on are built from source and everything beneath them comes from the cache.
        let substitutedGraph = substitutingCacheableTargets(
            in: sourceGraph,
            layerByTarget: layerByTarget,
            below: shape.layerCount - 2
        )

        let sourceTargets = sourceGraph.projects.values.reduce(0) { $0 + $1.targets.count }
        let remainingTargets = substitutedGraph.projects.values.reduce(0) { $0 + $1.targets.count }
        let substitutedNodes = substitutedGraph.dependencies.keys.filter {
            if case .xcframework = $0 { return true } else { return false }
        }.count

        print("""

        Source graph: \(sourceGraph.projects.count) projects, \(sourceTargets) targets, all built from source
        Warm graph:   \(remainingTargets) source targets, \(substitutedNodes) substituted xcframeworks

        """)

        let sourceMapping = try await measure { try await runFrameworkSearchPaths(on: sourceGraph) }
        let substitutedMapping = try await measure { try await runFrameworkSearchPaths(on: substitutedGraph) }
        let sourceProjectDependencies = try await measure { try runAllProjectDependencies(on: sourceGraph) }
        let substitutedProjectDependencies = try await measure { try runAllProjectDependencies(on: substitutedGraph) }

        report("FrameworkSearchPathsGraphMapper", source: sourceMapping, substituted: substitutedMapping)
        report("allProjectDependencies", source: sourceProjectDependencies, substituted: substitutedProjectDependencies)
    }

    // MARK: - Phases

    private func runFrameworkSearchPaths(on graph: Graph) async throws {
        _ = try await FrameworkSearchPathsGraphMapper().map(graph: graph, environment: MapperEnvironment())
    }

    private func runAllProjectDependencies(on graph: Graph) throws {
        let graphTraverser = GraphTraverser(graph: graph)
        for projectPath in graph.projects.keys {
            _ = try graphTraverser.allProjectDependencies(path: projectPath)
        }
    }

    // MARK: - Measurement

    /// Best of `iterations`, which is far more stable than a mean here: the work is single-threaded and CPU-bound,
    /// so run-to-run variation is scheduling noise that only ever adds time.
    private func measure(iterations: Int = 3, _ body: () async throws -> Void) async rethrows -> TimeInterval {
        var best = TimeInterval.greatestFiniteMagnitude
        for _ in 0 ..< iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            try await body()
            best = min(best, TimeInterval(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000)
        }
        return best
    }

    private func report(_ phase: String, source: TimeInterval, substituted: TimeInterval) {
        let ratio = source > 0 ? substituted / source : 0
        print(
            String(
                format: "%@: source %.2fs, substituted %.2fs (%.1fx)",
                phase,
                source,
                substituted,
                ratio
            )
        )
    }

    // MARK: - Graph construction

    /// Builds a layered dependency graph. Targets in a layer depend on targets in the layer beneath, spread across
    /// projects so the closure below any given target is wide as well as deep, as it is in a modularised app.
    private func makeGraph(shape: Shape) -> (graph: Graph, layerByTarget: [GraphDependency: Int]) {
        let root = try! AbsolutePath(validating: "/tmp/benchmark")

        var projects: [AbsolutePath: Project] = [:]
        var dependencies: [GraphDependency: Set<GraphDependency>] = [:]
        var targetsByLayer: [Int: [(name: String, path: AbsolutePath)]] = [:]

        for projectIndex in 0 ..< shape.projectCount {
            let projectPath = root.appending(component: "Project\(projectIndex)")
            var targets: [Target] = []

            for targetIndex in 0 ..< shape.targetsPerProject {
                let layer = (projectIndex * shape.targetsPerProject + targetIndex) % shape.layerCount
                let name = "Project\(projectIndex)Target\(targetIndex)"
                // Alternating linkage so both the static-closure and the dynamic-boundary traversals are exercised.
                let product: Product = targetIndex.isMultiple(of: 2) ? .framework : .staticFramework
                targets.append(Target.test(name: name, product: product))
                targetsByLayer[layer, default: []].append((name: name, path: projectPath))
            }

            projects[projectPath] = Project.test(
                path: projectPath,
                sourceRootPath: projectPath,
                name: "Project\(projectIndex)",
                targets: targets
            )
        }

        var layerByTarget: [GraphDependency: Int] = [:]

        for layer in 0 ..< shape.layerCount {
            guard let targets = targetsByLayer[layer] else { continue }
            let candidates = layer == 0 ? [] : (targetsByLayer[layer - 1] ?? [])

            for (offset, target) in targets.enumerated() {
                let node = GraphDependency.target(name: target.name, path: target.path)
                layerByTarget[node] = layer
                guard !candidates.isEmpty else {
                    dependencies[node] = []
                    continue
                }
                let edges = (0 ..< shape.fanOut).map { edgeIndex -> GraphDependency in
                    let candidate = candidates[(offset * shape.fanOut + edgeIndex) % candidates.count]
                    return .target(name: candidate.name, path: candidate.path)
                }
                dependencies[node] = Set(edges)
            }
        }

        return (
            Graph.test(
                path: root,
                projects: projects,
                dependencies: dependencies
            ),
            layerByTarget
        )
    }

    /// Replaces the lower layers of the graph with xcframework nodes and tree-shakes the replaced targets out of
    /// their projects, which is what `CacheGraphMutator` plus `TreeShakePrunedTargetsGraphMapper` produce on a warm
    /// run. The edge topology is preserved exactly, so the substituted graph differs from the source graph only in
    /// the kind of node that stands for a replaced module.
    ///
    /// The surviving upper layers are what generation still traverses from, and each of them now reaches a large
    /// precompiled closure rather than a target closure.
    private func substitutingCacheableTargets(in graph: Graph, layerByTarget: [GraphDependency: Int], below: Int) -> Graph {
        var replacements: [GraphDependency: GraphDependency] = [:]
        for (node, layer) in layerByTarget where layer < below {
            guard case let .target(name, path, _) = node else { continue }
            replacements[node] = makeXCFramework(name: name, path: path)
        }

        var dependencies: [GraphDependency: Set<GraphDependency>] = [:]
        for (node, edges) in graph.dependencies {
            let replacedNode = replacements[node] ?? node
            dependencies[replacedNode] = Set(edges.map { replacements[$0] ?? $0 })
        }

        let replacedNames: Set<String> = Set(replacements.keys.compactMap {
            guard case let .target(name, _, _) = $0 else { return nil }
            return name
        })

        var graph = graph
        graph.dependencies = dependencies
        graph.projects = graph.projects.mapValues { project in
            var project = project
            project.targets = project.targets.filter { !replacedNames.contains($0.value.name) }
            return project
        }
        return graph
    }

    /// Mirrors the metadata a cached artifact actually carries: a device and a simulator slice, and the
    /// `.swiftmodule` / `.modulemap` paths globbed out of the bundle.
    private func makeXCFramework(name: String, path: AbsolutePath) -> GraphDependency {
        let xcframeworkPath = path.appending(components: "Cache", "\(name).xcframework")
        let slices = ["ios-arm64", "ios-arm64-simulator"]
        return .testXCFramework(
            path: xcframeworkPath,
            infoPlist: XCFrameworkInfoPlist(
                libraries: slices.map { slice in
                    XCFrameworkInfoPlist.Library(
                        identifier: slice,
                        path: try! RelativePath(validating: "\(name).framework"),
                        mergeable: false,
                        platform: .iOS,
                        platformVariant: slice.hasSuffix("simulator") ? .simulator : nil,
                        architectures: [.arm64]
                    )
                }
            ),
            linking: .dynamic,
            swiftModules: slices.map {
                xcframeworkPath.appending(components: $0, "\(name).framework", "Modules", "\(name).swiftmodule")
            },
            moduleMaps: slices.map {
                xcframeworkPath.appending(components: $0, "\(name).framework", "Modules", "module.modulemap")
            }
        )
    }
}
