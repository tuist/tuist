import Path
import TuistCore
import XcodeGraph

/// Makes flat SwiftPM public include directories available as <Module/Header.h> without copying
/// every header into a framework. Explicit/umbrella module maps must not gain this namespace:
/// doing so changes __has_include branches in sibling shim modules.
struct SwiftPackageHeaderNamespaceMapper {
    func map(graph: Graph) -> (Graph, [SideEffectDescriptor]) {
        var graph = graph
        var sideEffects: [SideEffectDescriptor] = []
        for projectPath in graph.projects.keys.sorted() {
            guard var project = graph.projects[projectPath] else { continue }
            for targetName in project.targets.keys.sorted() {
                guard var target = project.targets[targetName],
                      let headers = target.headers,
                      let layout = headers.sourceLayout,
                      layout.usesDirectoryModuleMap
                else { continue }

                let includes = project.xcodeProjPath.parentDirectory.appending(
                    components: "Derived", "SwiftPackageIncludes", target.name
                )
                sideEffects.append(.symbolicLink(.init(
                    path: includes.appending(component: layout.moduleName),
                    destination: layout.publicHeaders
                )))
                let settings = target.settings ?? .default
                var base = settings.base
                let existing: [String]
                switch base["HEADER_SEARCH_PATHS"] {
                case let .array(values): existing = values
                case let .string(value): existing = [value]
                case nil: existing = ["$(inherited)"]
                }
                base["HEADER_SEARCH_PATHS"] = .array(
                    existing + ["$(SRCROOT)/\(includes.relative(to: project.path).pathString)"]
                )
                target.settings = settings.with(base: base)
                project.targets[targetName] = target
            }
            graph.projects[projectPath] = project
        }
        return (graph, sideEffects)
    }
}
