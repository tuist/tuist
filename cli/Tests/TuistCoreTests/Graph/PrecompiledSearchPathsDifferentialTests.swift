import Foundation
import Path
import Testing
import XcodeGraph
@testable import TuistCore

/// Differential harness for `precompiledSearchPathDependencies`.
///
/// That method derives framework search path inputs directly from the graph, where
/// `searchablePathDependencies` derives them by building a `GraphDependencyReference` for every reachable
/// dependency and letting the caller project it. The two must agree exactly: a missing search path breaks a
/// build, and an extra one can shadow a module with the wrong copy.
///
/// Agreement is checked over generated graphs rather than a handful of hand-written ones, because the
/// selection rules being mirrored are spread across `linkableDependencies` and three further unions, and the
/// interesting cases are combinations — a static xcframework behind a dynamic one behind a static framework,
/// a unit test whose host links a subset, a dependency made incompatible by a platform condition.
struct PrecompiledSearchPathsDifferentialTests {
    /// What the reference implementation says, projected the way the framework search paths mapper projects it.
    private func reference(
        _ traverser: GraphTraverser,
        path: AbsolutePath,
        name: String
    ) throws -> PrecompiledSearchPathDependencies {
        let references = try traverser.searchablePathDependencies(path: path, name: name)
        return PrecompiledSearchPathDependencies(
            precompiledPaths: Set(references.compactMap(\.precompiledPath)),
            sdkSearchPaths: Set(
                references.compactMap { reference -> String? in
                    guard case let .sdk(_, _, source, _) = reference else { return nil }
                    return source.frameworkSearchPath
                }
            )
        )
    }

    private struct Generator {
        private var seed: UInt64

        init(seed: UInt64) { self.seed = seed }

        mutating func next(_ bound: Int) -> Int {
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return Int(seed % UInt64(bound))
        }

        mutating func chance(_ percent: Int) -> Bool { next(100) < percent }
    }

    private static let root = try! AbsolutePath(validating: "/tmp/differential")

    // swiftlint:disable:next function_body_length
    private func makeGraph(seed: UInt64) -> Graph {
        var generator = Generator(seed: seed)
        let layers = 4 + generator.next(4)
        let perLayer = 4 + generator.next(6)

        var nodes: [[GraphDependency]] = []
        var targets: [AbsolutePath: [String: Target]] = [:]
        var identifier = 0

        let products: [Product] = [
            .framework, .staticFramework, .staticLibrary, .dynamicLibrary, .app, .unitTests, .bundle, .appClip,
        ]

        for _ in 0 ..< layers {
            var layer: [GraphDependency] = []
            for _ in 0 ..< perLayer {
                identifier += 1
                switch generator.next(6) {
                case 0:
                    layer.append(
                        .testXCFramework(
                            path: Self.root.appending(component: "X\(identifier).xcframework"),
                            linking: generator.chance(50) ? .dynamic : .static,
                            swiftModules: generator.chance(50)
                                ? [Self.root.appending(component: "X\(identifier).swiftmodule")] : [],
                            moduleMaps: generator.chance(50)
                                ? [Self.root.appending(component: "X\(identifier).modulemap")] : []
                        )
                    )
                case 1:
                    layer.append(
                        .testFramework(
                            path: Self.root.appending(component: "F\(identifier).framework"),
                            binaryPath: Self.root.appending(components: "F\(identifier).framework", "F\(identifier)"),
                            linking: generator.chance(50) ? .dynamic : .static
                        )
                    )
                case 2:
                    layer.append(
                        .library(
                            path: Self.root.appending(component: "L\(identifier).a"),
                            publicHeaders: Self.root.appending(component: "Headers\(identifier)"),
                            linking: generator.chance(50) ? .dynamic : .static,
                            architectures: [.arm64],
                            swiftModuleMap: nil
                        )
                    )
                case 3:
                    layer.append(
                        .sdk(
                            name: "SDK\(identifier).framework",
                            path: Self.root.appending(component: "SDK\(identifier).framework"),
                            status: .required,
                            source: generator.chance(50) ? .developer : .system
                        )
                    )
                default:
                    let projectPath = Self.root.appending(component: "Project\(identifier % 5)")
                    let name = "T\(identifier)"
                    targets[projectPath, default: [:]][name] = Target.test(
                        name: name,
                        product: products[generator.next(products.count)]
                    )
                    layer.append(.target(name: name, path: projectPath))
                }
            }
            nodes.append(layer)
        }

        var dependencies: [GraphDependency: Set<GraphDependency>] = [:]
        var conditions: [GraphEdge: PlatformCondition] = [:]
        for (layerIndex, layer) in nodes.enumerated() {
            for node in layer {
                guard layerIndex > 0 else {
                    dependencies[node] = []
                    continue
                }
                var edges: Set<GraphDependency> = []
                for _ in 0 ..< (1 + generator.next(3)) {
                    let child = nodes[layerIndex - 1][generator.next(perLayer)]
                    edges.insert(child)
                    // Platform conditions are what make a dependency droppable, so some edges carry one.
                    if generator.chance(20) {
                        conditions[GraphEdge(from: node, to: child)] = .when([generator.chance(50) ? .ios : .macos])
                    }
                }
                dependencies[node] = edges
            }
        }

        // Conflicting condition chains. A single conditioned edge only ever narrows a dependency; it takes two
        // conditions disagreeing along a path for `combinedCondition` to report `.incompatible`, which is the
        // case the candidate's admission guard exists for. Left to chance those are vanishingly rare.
        for (edge, condition) in conditions where generator.chance(60) {
            let iOSOnly = PlatformCondition.when([.ios])
            let macOSOnly = PlatformCondition.when([.macos])
            guard let iOSOnly, let macOSOnly else { continue }
            let opposite = condition == iOSOnly ? macOSOnly : iOSOnly
            for child in dependencies[edge.to, default: []] {
                conditions[GraphEdge(from: edge.to, to: child)] = opposite
            }
        }

        // Static xcframeworks sitting behind a dynamic one, which is the shape binary-cache substitution
        // produces and the rule `staticXCFrameworksLinkedByDynamicXCFrameworkDependencies` exists for.
        var absorbed = 0
        for layer in nodes {
            for node in layer {
                guard case let .xcframework(xcframework) = node, xcframework.linking == .dynamic,
                      generator.chance(70)
                else { continue }
                absorbed += 1
                let staticSibling = GraphDependency.testXCFramework(
                    path: Self.root.appending(component: "Absorbed\(absorbed).xcframework"),
                    linking: .static,
                    swiftModules: [Self.root.appending(component: "Absorbed\(absorbed).swiftmodule")]
                )
                dependencies[node, default: []].insert(staticSibling)
                dependencies[staticSibling] = []
            }
        }

        let projects = Dictionary(uniqueKeysWithValues: targets.map { path, projectTargets in
            (
                path,
                Project.test(
                    path: path,
                    sourceRootPath: path,
                    name: path.basename,
                    targets: Array(projectTargets.values)
                )
            )
        })
        return Graph.test(path: Self.root, projects: projects, dependencies: dependencies, dependencyConditions: conditions)
    }

    @Test func matchesSearchablePathDependenciesAcrossGeneratedGraphs() throws {
        var divergences: [String] = []
        var comparisons = 0
        // Coverage counters. A differential harness is only worth the name if the corpus reaches the rules
        // being mirrored, so the run asserts it did rather than assuming it.
        var withPrecompiledPaths = 0
        var withSDKSearchPaths = 0
        var withStaticsBehindDynamicXCFramework = 0
        var withConditionDroppedDependency = 0

        for iteration in 0 ..< 60 {
            let graph = makeGraph(seed: 0x2545_F491_4F6C_DD1D &+ UInt64(iteration &* 7919))
            let traverser = GraphTraverser(graph: graph)
            for (projectPath, project) in graph.projects {
                for name in project.targets.keys {
                    comparisons += 1
                    let expected = try reference(traverser, path: projectPath, name: name)
                    let got = traverser.precompiledSearchPathDependencies(path: projectPath, name: name)

                    if !expected.precompiledPaths.isEmpty { withPrecompiledPaths += 1 }
                    if !expected.sdkSearchPaths.isEmpty { withSDKSearchPaths += 1 }
                    if !traverser.staticXCFrameworksLinkedByDynamicXCFrameworkDependencies(
                        path: projectPath,
                        name: name
                    ).isEmpty {
                        withStaticsBehindDynamicXCFramework += 1
                    }
                    let from = GraphDependency.target(name: name, path: projectPath)
                    if traverser.filterDependencies(from: from).contains(where: { dependency in
                        guard case .incompatible = traverser.combinedCondition(to: dependency, from: from) else {
                            return false
                        }
                        switch dependency {
                        case .xcframework, .framework, .library, .foreignBuildOutput, .sdk: return true
                        case .bundle, .macro, .packageProduct, .target: return false
                        }
                    }) {
                        withConditionDroppedDependency += 1
                    }

                    guard got != expected else { continue }
                    divergences.append(
                        """
                        seed \(iteration), target \(name):
                          precompiled only in reference: \
                        \(expected.precompiledPaths.subtracting(got.precompiledPaths).map(\.basename).sorted())
                          precompiled only in candidate: \
                        \(got.precompiledPaths.subtracting(expected.precompiledPaths).map(\.basename).sorted())
                          sdk only in reference: \(expected.sdkSearchPaths.subtracting(got.sdkSearchPaths).sorted())
                          sdk only in candidate: \(got.sdkSearchPaths.subtracting(expected.sdkSearchPaths).sorted())
                        """
                    )
                }
            }
        }

        #expect(comparisons > 500, "the generator should be producing a meaningful number of targets")
        #expect(withPrecompiledPaths > 100, "corpus reaches precompiled artifacts (got \(withPrecompiledPaths))")
        #expect(withSDKSearchPaths > 20, "corpus reaches developer SDKs (got \(withSDKSearchPaths))")
        #expect(
            withStaticsBehindDynamicXCFramework > 10,
            "corpus reaches statics behind a dynamic xcframework (got \(withStaticsBehindDynamicXCFramework))"
        )
        #expect(
            withConditionDroppedDependency > 5,
            "corpus reaches platform conditions that drop a dependency (got \(withConditionDroppedDependency))"
        )
        #expect(
            divergences.isEmpty,
            "\(divergences.count) of \(comparisons) targets diverged:\n\(divergences.prefix(10).joined(separator: "\n"))"
        )
    }
}
