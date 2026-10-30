import Path
import TuistCore
import XcodeGraph

/// Binds source package headers only after cache replacement, so removed source targets cannot
/// leave their module maps and search paths in a consumer of the cached copy.
public struct SwiftPackageSourceHeadersMapper: GraphMapping {
    public init() {}

    public func map(graph: Graph, environment: MapperEnvironment) throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        let traverser = GraphTraverser(graph: graph)
        let sources = Dictionary(uniqueKeysWithValues: traverser.allTargets().filter {
            $0.target.headers?.sourceLayout != nil && !$0.target.metadata.tags.contains("tuist:binary-sources")
        }.map { (GraphDependency.target(name: $0.target.name, path: $0.path), $0) })
        guard !sources.isEmpty else { return (graph, [], environment) }
        var dependents: [GraphDependency: Set<GraphDependency>] = [:]
        for (origin, dependencies) in graph.dependencies {
            guard case .target = origin else { continue }
            for dependency in dependencies {
                guard case .target = dependency else { continue }
                dependents[dependency, default: []].insert(origin)
            }
        }
        var dependenciesByTarget: [GraphDependency: Set<GraphDependency>] = [:]
        for source in sources.keys {
            var queue = Array(dependents[source, default: []])
            var visited: Set<GraphDependency> = []
            while let dependent = queue.popLast() {
                guard visited.insert(dependent).inserted else { continue }
                dependenciesByTarget[dependent, default: []].insert(source)
                queue += dependents[dependent, default: []]
            }
        }
        var result = graph
        for origin in traverser.allTargets() {
            guard let project = graph.projects[origin.path] else { continue }
            let projectDirectory = project.xcodeProjPath.parentDirectory
            let dependency = GraphDependency.target(name: origin.target.name, path: origin.path)
            var includes: Set<String> = []
            var moduleMaps: Set<String> = []
            for next in dependenciesByTarget[dependency, default: []] {
                guard let source = sources[next], let layout = source.target.headers?.sourceLayout else { continue }
                moduleMaps
                    .insert("-fmodule-map-file=\"$(PROJECT_DIR)/\(layout.moduleMap.relative(to: projectDirectory).pathString)\"")
                let paths: [String]
                switch source.target.settings?.base["HEADER_SEARCH_PATHS"] {
                case let .array(values): paths = values
                case let .string(value): paths = [value]
                case nil: paths = [layout.publicHeaders.pathString]
                }
                for value in paths where value != "$(inherited)" {
                    let resolved = value.replacingOccurrences(of: "$(SRCROOT)", with: source.path.pathString)
                        .replacingOccurrences(
                            of: "$(PROJECT_DIR)",
                            with: graph.projects[source.path]?.xcodeProjPath.parentDirectory.pathString ?? source.path.pathString
                        )
                        .replacingOccurrences(of: "$(SOURCE_ROOT)", with: source.path.pathString)
                    if let path = try? AbsolutePath(validating: resolved) {
                        includes.insert("\"$(PROJECT_DIR)/\(path.relative(to: projectDirectory).pathString)\"")
                    } else {
                        includes.insert(resolved)
                    }
                }
            }
            guard !moduleMaps.isEmpty else { continue }
            var target = origin.target
            let settings = target.settings ?? .default
            let additions: SettingsDictionary = [
                "HEADER_SEARCH_PATHS": .array(includes.sorted()),
                "OTHER_CFLAGS": .array(moduleMaps.sorted()),
                "OTHER_SWIFT_FLAGS": .array(moduleMaps.sorted().flatMap { ["-Xcc", $0] }),
            ]
            target.settings = settings.appendingBuildSettings(additions)
            result.projects[origin.path]?.targets[target.name] = target
        }
        return (result, [], environment)
    }
}
