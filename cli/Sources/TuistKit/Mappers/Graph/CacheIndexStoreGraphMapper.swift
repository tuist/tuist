import Foundation
import Path
import TuistCore
import XcodeGraph

/// Appends the compiler flags that make cache-warm builds emit hermetic Xcode index data.
///
/// Index units embed the absolute path of every source file and of the compiler's output. Left
/// alone, those would be the warm machine's paths, which are meaningless on a developer's machine
/// and vary run to run. `-file-prefix-map` rewrites the source root and derived data root to stable
/// tokens (`CacheIndexStore.sourceRootToken` / `.buildRootToken`) so the artifact is machine
/// independent; the consumer remaps the tokens back when importing. `-index-ignore-system-modules`
/// keeps the store to the module's own symbols.
///
/// The flags are added per target with `combine(with:)`, which appends to each target's existing
/// `OTHER_SWIFT_FLAGS` / `OTHER_C_FLAGS` rather than replacing them, so a target's own flags are
/// preserved.
public struct CacheIndexStoreGraphMapper: GraphMapping {
    public init() {}

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) async throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        let sourceRoot = graph.path.pathString
        let swiftFlags: [String] = [
            "-file-prefix-map", "\(sourceRoot)=\(CacheIndexStore.sourceRootToken)",
            "-index-ignore-system-modules",
        ]
        let cFlags: [String] = [
            "-ffile-prefix-map=\(sourceRoot)=\(CacheIndexStore.sourceRootToken)",
        ]
        let indexSettings: SettingsDictionary = [
            "OTHER_SWIFT_FLAGS": .array(swiftFlags),
            "OTHER_C_FLAGS": .array(cFlags),
        ]

        var graph = graph
        graph.projects = graph.projects.mapValues { project in
            var project = project
            project.targets = project.targets.mapValues { target in
                var target = target
                let settings = target.settings ?? Settings(
                    base: [:],
                    configurations: [:],
                    defaultSettings: project.settings.defaultSettings
                )
                target.settings = settings.with(
                    base: settings.base.combine(with: indexSettings)
                )
                return target
            }
            return project
        }

        return (graph, [], environment)
    }
}
