import FileSystem
import Path
import TuistCore
import XcodeGraph

/// Restores portable SwiftPM headers without mixing vendor and ProcessXCFramework copies.
public struct SwiftPackageCachedHeadersMapper: GraphMapping {
    private struct Slice {
        let sdk: String
        let platform: PlatformFilter
        let directory: AbsolutePath
        let productsDirectory: String
        let metadata: [SwiftPackageHeadersExporter.Metadata]
    }

    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) async throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        let graphs = [graph, environment.initialGraphWithSources].compactMap { $0 }
        // Ordinary binary dependencies have no portable metadata. Probe each artifact once
        // before doing any per-target traversal, then walk backwards only from matching artifacts.
        let artifacts = try await exportedSlices(in: graphs)
        guard !artifacts.isEmpty else { return (graph, [], environment) }
        let consumers = consumers(of: Set(artifacts.keys), in: graphs)
        let traverser = GraphTraverser(graph: graph)
        let sourceTraverser = environment.initialGraphWithSources.map { GraphTraverser(graph: $0) }
        let processors = processors(of: Set(artifacts.keys), graph: graph, traverser: traverser)
        var result = graph
        for origin in consumers.keys.sorted() {
            guard case let .target(name, path, _) = origin,
                  var project = result.projects[path], var target = project.targets[name]
            else { continue }
            let reachable = reachableDependencies(from: origin, in: graph)
            let sourceReachable = environment.initialGraphWithSources.map { reachableDependencies(from: origin, in: $0) } ?? []
            var additions: SettingsDictionary = [:]
            for dependency in consumers[origin, default: []].sorted() {
                let dependencyTraverser: GraphTraverser
                if reachable.contains(dependency) {
                    dependencyTraverser = traverser
                } else if sourceReachable.contains(dependency), let sourceTraverser {
                    dependencyTraverser = sourceTraverser
                } else {
                    continue
                }
                guard case let .condition(condition) = dependencyTraverser.combinedCondition(to: dependency, from: origin)
                else { continue }
                for slice in artifacts[dependency, default: []] {
                    if let condition, !condition.platformFilters.contains(slice.platform) { continue }
                    let processed = processors[dependency, default: [:]].contains { processor, platforms in
                        guard platforms.contains(slice.platform) else { return false }
                        if processor == origin { return true }
                        // combinedCondition describes conditions, not reachability. A sibling or
                        // downstream app's processing step cannot satisfy this consumer's inputs.
                        guard reachable.contains(processor),
                              case let .condition(condition) = traverser.combinedCondition(to: processor, from: origin)
                        else { return false }
                        return condition?.platformFilters.contains(slice.platform) ?? true
                    }
                    additions = additions.combine(with: try settings(
                        for: slice, processed: processed, projectPath: project.xcodeProjPath.parentDirectory
                    ))
                }
            }
            let settings = target.settings ?? .default
            target.settings = settings.appendingBuildSettings(additions)
            project.targets[name] = target
            result.projects[path] = project
        }
        return (result, [], environment)
    }

    private func settings(for slice: Slice, processed: Bool, projectPath: AbsolutePath) throws -> SettingsDictionary {
        func searchPath(_ relative: String) throws -> String? {
            let include = slice.directory.appending(try RelativePath(validating: relative))
            guard include.isDescendant(of: slice.directory) else { return nil }
            return processed
                ? "$(BUILT_PRODUCTS_DIR)/\(slice.productsDirectory)/\(relative)"
                : "$(PROJECT_DIR)/\(include.relative(to: projectPath).pathString)"
        }
        var result: SettingsDictionary = [:]
        for metadata in slice.metadata {
            let includes = try [metadata.publicDirectory, metadata.namespaceDirectory].compactMap { relative in
                try relative.flatMap { try searchPath($0) }.map { "\"\($0)\"" }
            }
            result = result.combine(with: ["HEADER_SEARCH_PATHS[\(slice.sdk)]": .array(includes)])
            if let moduleMap = metadata.moduleMap, let mapPath = try searchPath(moduleMap) {
                // Explicit loading supports multiple top-level modules and names different from
                // the artifact, and does not discover a sibling target's processed copy.
                let flag = "-fmodule-map-file=\"\(mapPath)\""
                result = result.combine(with: [
                    "OTHER_CFLAGS[\(slice.sdk)]": .array([flag]),
                    "OTHER_SWIFT_FLAGS[\(slice.sdk)]": .array(["-Xcc", flag]),
                ])
            }
        }
        return result
    }

    private func exportedSlices(in graphs: [Graph]) async throws -> [GraphDependency: [Slice]] {
        let dependencies = Set(graphs.flatMap { $0.dependencies.values.flatMap { $0 } })
        var result: [GraphDependency: [Slice]] = [:]
        var inspected: [AbsolutePath: [Slice]] = [:]
        for dependency in dependencies.sorted() {
            guard case let .xcframework(xcframework) = dependency else { continue }
            if let slices = inspected[xcframework.path] {
                if !slices.isEmpty { result[dependency] = slices }
                continue
            }
            var slices: [Slice] = []
            for library in xcframework.infoPlist.libraries {
                let framework = library.path.extension == "framework"
                let slice = xcframework.path.appending(component: library.identifier)
                let directory = framework ? slice.appending(library.path) : library.headersPath.map { slice.appending($0) }
                guard let directory else { continue }
                let manifests: [AbsolutePath]
                if framework {
                    let manifest = directory.appending(components: "PrivateHeaders", SwiftPackageHeadersExporter.metadataFileName)
                    manifests = try await fileSystem.exists(manifest) ? [manifest] : []
                } else {
                    manifests = try await fileSystem.glob(
                        directory: directory, include: ["*/\(SwiftPackageHeadersExporter.metadataFileName)"]
                    ).collect().sorted()
                }
                guard !manifests.isEmpty else { continue }
                var metadata: [SwiftPackageHeadersExporter.Metadata] = []
                for manifest in manifests {
                    metadata.append(try await fileSystem.readJSONFile(at: manifest))
                }
                slices.append(Slice(
                    sdk: library.sdkCondition, platform: library.platformFilter, directory: directory,
                    productsDirectory: framework ? library.path.pathString : "include", metadata: metadata
                ))
            }
            inspected[xcframework.path] = slices
            if !slices.isEmpty { result[dependency] = slices }
        }
        return result
    }

    private func consumers(of artifacts: Set<GraphDependency>, in graphs: [Graph]) -> [GraphDependency: Set<GraphDependency>] {
        var dependents: [GraphDependency: Set<GraphDependency>] = [:]
        for graph in graphs {
            for (origin, dependencies) in graph.dependencies {
                for dependency in dependencies {
                    dependents[dependency, default: []].insert(origin)
                }
            }
        }
        var result: [GraphDependency: Set<GraphDependency>] = [:]
        for artifact in artifacts {
            var queue = [artifact]
            var visited: Set<GraphDependency> = []
            while let dependency = queue.popLast() {
                guard visited.insert(dependency).inserted else { continue }
                queue += dependents[dependency, default: []]
                if case .target = dependency { result[dependency, default: []].insert(artifact) }
            }
        }
        return result
    }

    private func reachableDependencies(from origin: GraphDependency, in graph: Graph) -> Set<GraphDependency> {
        var queue = Array(graph.dependencies[origin, default: []])
        var visited: Set<GraphDependency> = []
        while let dependency = queue.popLast() {
            guard visited.insert(dependency).inserted else { continue }
            queue += graph.dependencies[dependency, default: []]
        }
        return visited
    }

    private func processors(
        of artifacts: Set<GraphDependency>, graph: Graph, traverser: GraphTraverser
    ) -> [GraphDependency: [GraphDependency: Set<PlatformFilter>]] {
        var result: [GraphDependency: [GraphDependency: Set<PlatformFilter>]] = [:]
        for artifact in artifacts {
            guard case let .xcframework(xcframework) = artifact else { continue }
            for reference in traverser.targetsProcessingStaticXCFramework(at: xcframework.path)
                where !reference.target.metadata.tags.contains("tuist:binary-sources")
            {
                let origin = GraphDependency.target(name: reference.target.name, path: reference.graphTarget.path)
                for destination in reference.target.destinations
                    where reference.condition?.platformFilters.contains(destination.platformFilter) ?? true
                {
                    result[artifact, default: [:]][origin, default: []].insert(destination.platformFilter)
                }
            }
            for (origin, dependencies) in graph.dependencies where dependencies.contains(artifact) {
                guard case let .target(name, path, _) = origin, let target = graph.projects[path]?.targets[name],
                      !target.metadata.tags.contains("tuist:binary-sources") else { continue }
                for destination in target.destinations
                    where graph.dependencyConditions[(origin, artifact)]?.platformFilters
                    .contains(destination.platformFilter) ?? true
                {
                    result[artifact, default: [:]][origin, default: []].insert(destination.platformFilter)
                }
            }
        }
        return result
    }
}
