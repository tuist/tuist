import Foundation
import TuistCore
import XcodeGraph

/// Marks the repository-owned binaries of a `tuist cache --coverage` warm, so the coverage settings the
/// warm passes on the command line (`InstrumentedBinaryCacheWarm`) apply to them and to nothing else.
///
/// The marker is a target setting rather than the coverage settings themselves because a command-line
/// setting beats a target's own `OTHER_SWIFT_FLAGS`, while a setting a target overrides without
/// `$(inherited)` would be lost. It lands only on frameworks and libraries: the same xcodebuild
/// invocation builds external packages, which must stay plain, and a repository macro or bundle built as
/// a dependency has no coverage to measure, and a macro plugin linked against the profile runtime would
/// write a profile wherever it exits.
public struct InstrumentedBinaryCacheWarmGraphMapper: GraphMapping {
    private static let instrumentedProducts: Set<Product> = [.framework, .staticFramework, .staticLibrary, .dynamicLibrary]

    public init() {}

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) async throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        var graph = graph
        graph.projects = graph.projects.mapValues { project in
            // The targets a coverage run keys on coverage (`CacheGraphContentHasher`): no external hash.
            guard project.externalHash == nil else { return project }
            var project = project
            project.targets = project.targets.mapValues { target in
                guard Self.instrumentedProducts.contains(target.product) else { return target }
                var target = target
                target.settings = Settings(
                    base: (target.settings?.base ?? [:])
                        .merging([InstrumentedBinaryCacheWarm.markerSetting: "YES"]) { _, marker in marker },
                    baseDebug: target.settings?.baseDebug ?? [:],
                    configurations: target.settings?.configurations ?? [:],
                    defaultSettings: target.settings?.defaultSettings ?? project.settings.defaultSettings,
                    defaultConfiguration: target.settings?.defaultConfiguration
                )
                return target
            }
            return project
        }
        return (graph, [], environment)
    }
}
