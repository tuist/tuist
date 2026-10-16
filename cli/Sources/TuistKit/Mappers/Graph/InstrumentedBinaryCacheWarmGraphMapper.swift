import Foundation
import TuistCore
import XcodeGraph

/// Marks every repository-owned project of a `tuist cache --coverage` warm, so the coverage settings the
/// warm passes on the command line (`InstrumentedBinaryCacheWarm`) apply to its targets and to no other.
///
/// The marker is a project setting rather than the coverage settings themselves because a command-line
/// setting beats a target's own `OTHER_SWIFT_FLAGS`, while a project setting a target overrides without
/// `$(inherited)` would be lost; and because the same xcodebuild invocation builds external packages,
/// which must stay plain.
public struct InstrumentedBinaryCacheWarmGraphMapper: GraphMapping {
    public init() {}

    public func map(graph: Graph, environment: MapperEnvironment) async throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        var graph = graph
        graph.projects = graph.projects.mapValues { project in
            guard case .local = project.type else { return project }
            var project = project
            let settings = project.settings
            project.settings = Settings(
                base: settings.base.merging([InstrumentedBinaryCacheWarm.markerSetting: "YES"]) { _, marker in marker },
                baseDebug: settings.baseDebug,
                configurations: settings.configurations,
                defaultSettings: settings.defaultSettings,
                defaultConfiguration: settings.defaultConfiguration
            )
            return project
        }
        return (graph, [], environment)
    }
}
