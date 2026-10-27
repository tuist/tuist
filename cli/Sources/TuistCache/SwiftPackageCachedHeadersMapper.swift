import FileSystem
import Path
import TuistCore
import XcodeGraph

/// Restores the original raw include search path of cached SwiftPM C modules. Custom module maps
/// keep an empty framework Headers directory, so caching cannot change shim __has_include branches.
public struct SwiftPackageCachedHeadersMapper: GraphMapping {
    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) async throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        guard graph.dependencies.values.contains(where: { dependencies in
            dependencies.contains {
                if case .xcframework = $0 { return true }
                return false
            }
        }) else { return (graph, [], environment) }
        var graph = graph
        let traverser = GraphTraverser(graph: graph)
        let sourceTraverser = environment.initialGraphWithSources.map { GraphTraverser(graph: $0) }
        var processedPlatforms = directlyProcessedPlatforms(graph: graph, sourceGraph: environment.initialGraphWithSources)
        var inspectedProcessors: Set<AbsolutePath> = []
        var metadataByDirectory: [AbsolutePath: [SwiftPackageHeadersExporter.Metadata]] = [:]
        var inspectedDirectories: Set<AbsolutePath> = []
        for projectPath in graph.projects.keys.sorted() {
            guard var project = graph.projects[projectPath] else { continue }
            for targetName in project.targets.keys.sorted() {
                guard var target = project.targets[targetName] else { continue }
                let origin = GraphDependency.target(name: targetName, path: projectPath)
                var queue = Array(graph.dependencies[origin, default: []])
                let recovered = sourceTraverser?.staticObjcXCFrameworksReachableViaCachedTargets(
                    path: projectPath, name: targetName, currentGraph: graph
                ) ?? []
                queue += recovered
                var visited: Set<GraphDependency> = []
                var pathsBySDK: [String: Set<String>] = [:]
                while let dependency = queue.popLast() {
                    guard visited.insert(dependency).inserted else { continue }
                    queue += graph.dependencies[dependency, default: []]
                    let dependencyTraverser = recovered.contains(dependency) ? (sourceTraverser ?? traverser) : traverser
                    guard case let .xcframework(xcframework) = dependency,
                          case let .condition(condition) = dependencyTraverser.combinedCondition(to: dependency, from: origin)
                    else { continue }
                    if inspectedProcessors.insert(xcframework.path).inserted {
                        for reference in traverser.targetsProcessingStaticXCFramework(at: xcframework.path)
                            where !reference.target.metadata.tags.contains("tuist:binary-sources")
                        {
                            for destination in reference.target.destinations
                                where reference.condition?.platformFilters.contains(destination.platformFilter) ?? true
                            {
                                processedPlatforms[xcframework.path, default: []].insert(destination.platformFilter)
                            }
                        }
                    }
                    for library in xcframework.infoPlist.libraries {
                        if let condition, !condition.platformFilters.contains(library.platformFilter) { continue }
                        let slice = xcframework.path.appending(component: library.identifier)
                        let directory = library.path.extension == "framework"
                            ? slice.appending(library.path)
                            : library.headersPath.map { slice.appending($0) }
                        guard let directory else { continue }
                        if inspectedDirectories.insert(directory).inserted {
                            let manifest = directory.appending(component: SwiftPackageHeadersExporter.Metadata.fileName)
                            if try await fileSystem.exists(manifest) {
                                metadataByDirectory[directory] = [try await fileSystem.readJSONFile(at: manifest)]
                            } else if library.path.extension != "framework" {
                                let manifests = try await fileSystem.glob(
                                    directory: directory, include: ["*/\(SwiftPackageHeadersExporter.Metadata.fileName)"]
                                ).collect()
                                var metadata: [SwiftPackageHeadersExporter.Metadata] = []
                                for manifest in manifests.sorted() {
                                    metadata.append(try await fileSystem.readJSONFile(at: manifest))
                                }
                                metadataByDirectory[directory] = metadata
                            }
                        }
                        for metadata in metadataByDirectory[directory, default: []] {
                            for relative in [metadata.publicDirectory, metadata.namespaceDirectory].compactMap({ $0 }) {
                                let include = directory.appending(try RelativePath(validating: relative))
                                guard include.isDescendant(of: directory) else { continue }
                                let searchPath: String
                                if processedPlatforms[xcframework.path, default: []].contains(library.platformFilter) {
                                    // Module maps and raw includes must refer to the same physical files.
                                    // Mixing the vendor tree with ProcessXCFramework's copy redeclares types.
                                    let productDirectory = library.path.extension == "framework" ? library.path.pathString : "include"
                                    searchPath = "$(BUILT_PRODUCTS_DIR)/\(productDirectory)/\(relative)"
                                } else {
                                    searchPath = "$(SRCROOT)/\(include.relative(to: project.path).pathString)"
                                }
                                pathsBySDK[library.sdkCondition, default: []].insert("\"\(searchPath)\"")
                            }
                        }
                    }
                }
                guard !pathsBySDK.isEmpty else { continue }
                let settings = target.settings ?? .default
                var base = settings.base
                for (sdk, paths) in pathsBySDK {
                    let key = "HEADER_SEARCH_PATHS[\(sdk)]"
                    let existing: [String]
                    switch base[key] {
                    case let .array(values): existing = values
                    case let .string(value): existing = [value]
                    case nil: existing = ["$(inherited)"]
                    }
                    base[key] = .array(existing + paths.sorted())
                }
                target.settings = settings.with(base: base)
                project.targets[targetName] = target
            }
            graph.projects[projectPath] = project
        }
        return (graph, [], environment)
    }

    private func directlyProcessedPlatforms(graph: Graph, sourceGraph: Graph?) -> [AbsolutePath: Set<PlatformFilter>] {
        var result: [AbsolutePath: Set<PlatformFilter>] = [:]
        for source in [graph, sourceGraph].compactMap({ $0 }) {
            for (origin, dependencies) in source.dependencies {
                guard case let .target(name, path, _) = origin,
                      let target = graph.projects[path]?.targets[name],
                      !target.metadata.tags.contains("tuist:binary-sources")
                else { continue }
                for dependency in dependencies {
                    guard case let .xcframework(xcframework) = dependency else { continue }
                    let condition = source.dependencyConditions[(origin, dependency)]
                    for destination in target.destinations
                        where condition?.platformFilters.contains(destination.platformFilter) ?? true
                    {
                        result[xcframework.path, default: []].insert(destination.platformFilter)
                    }
                }
            }
        }
        return result
    }
}
