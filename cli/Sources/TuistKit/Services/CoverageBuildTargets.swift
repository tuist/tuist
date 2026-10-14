import Foundation
import Path
import TuistCore
import XcodeGraph

/// The targets a test run's coverage describes, from the project graph: every target the
/// tested schemes build or test and everything those depend on, with the files each compiles
/// and whether it is a test bundle. The binary cache replaces targets with xcframeworks before
/// the schemes are generated, so the targets come from the graph as it was before that, and a
/// replaced target carries the slices of the xcframework the generated project links instead.
/// Files are absolute here; the build sources relativize them to the checkout.
enum CoverageBuildTargets {
    static func targets(schemes: [Scheme], graph: Graph, generatedGraph: Graph) -> [CoverageBuildTarget] {
        let traverser = GraphTraverser(graph: graph)
        let references = schemes.flatMap { scheme in
            (scheme.buildAction?.targets ?? [])
                + (scheme.testAction?.targets.map(\.target) ?? [])
                + (scheme.testAction?.testPlans ?? []).flatMap { $0.testTargets.map(\.target) }
        }
        let roots = references.compactMap { reference -> GraphTarget? in
            guard let project = graph.projects[reference.projectPath],
                  let target = project.targets[reference.name] else { return nil }
            return GraphTarget(path: reference.projectPath, target: target, project: project)
        }
        let closure = Set(roots).union(traverser.allTargetDependencies(traversingFromTargets: roots))

        let xcframeworks = Dictionary(
            generatedGraph.dependencies.flatMap { [$0.key] + Array($0.value) }
                .compactMap { dependency -> (String, GraphDependency.XCFramework)? in
                    guard case let .xcframework(xcframework) = dependency else { return nil }
                    return (xcframework.path.basenameWithoutExt, xcframework)
                },
            uniquingKeysWith: { first, _ in first }
        )

        return closure
            .map { graphTarget in
                let target = graphTarget.target
                let replaced = generatedGraph.projects[graphTarget.path]?.targets[target.name] == nil
                return CoverageBuildTarget(
                    name: target.productNameWithExtension,
                    isTest: target.product.testsBundle,
                    files: target.sources.map(\.path.pathString).sorted(),
                    binaries: replaced ? binaries(of: xcframeworks[target.productName]) : []
                )
            }
            .sorted { $0.name < $1.name }
    }

    /// One slice per library of the xcframework, each with its binary inside.
    static func binaries(of xcframework: GraphDependency.XCFramework?) -> [CoverageBuildTarget.Binary] {
        guard let xcframework else { return [] }
        return xcframework.infoPlist.libraries.map { library in
            var binary = xcframework.path.appending(components: library.identifier).appending(library.path)
            if library.path.extension == "framework" {
                binary = binary.appending(component: library.binaryName)
            }
            return CoverageBuildTarget.Binary(
                path: binary.pathString,
                platform: library.platform.rawValue,
                simulator: library.platformVariant == .simulator
            )
        }
    }
}
