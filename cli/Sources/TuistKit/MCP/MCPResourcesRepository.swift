import FileSystem
import Foundation
import MCP
import Path
import SwiftyJSON
import TuistCore
import TuistGenerator
import TuistLoader
import TuistSupport
import XcodeGraph
import XcodeGraphMapper

protocol MCPResourcesRepositorying {
    func list() async throws -> ListResources.Result
    func listTemplates() async throws -> ListResourceTemplates.Result
    func read(_ resource: ReadResource.Parameters) async throws -> ReadResource.Result
}

struct MCPResourcesRepository: MCPResourcesRepositorying {
    private let fileSystem: FileSysteming
    private let manifestGraphLoader: ManifestGraphLoading
    private let manifestLoader: ManifestLoading
    private let xcodeGraphMapper: XcodeGraphMapping
    private let jsonEncoder = JSONEncoder()
    private let configLoader: ConfigLoading

    init() {
        let manifestLoader = ManifestLoaderFactory()
            .createManifestLoader()
        let manifestGraphLoader = ManifestGraphLoader(
            manifestLoader: manifestLoader,
            workspaceMapper: SequentialWorkspaceMapper(mappers: []),
            graphMapper: SequentialGraphMapper([])
        )
        self.init(
            fileSystem: FileSystem(),
            manifestGraphLoader: manifestGraphLoader,
            manifestLoader: manifestLoader,
            xcodeGraphMapper: XcodeGraphMapper(),
            configLoader: ConfigLoader()
        )
    }

    init(
        fileSystem: FileSysteming,
        manifestGraphLoader: ManifestGraphLoading,
        manifestLoader: ManifestLoading,
        xcodeGraphMapper: XcodeGraphMapping,
        configLoader: ConfigLoading
    ) {
        self.fileSystem = fileSystem
        self.manifestGraphLoader = manifestGraphLoader
        self.manifestLoader = manifestLoader
        self.xcodeGraphMapper = xcodeGraphMapper
        self.configLoader = configLoader
    }

    func list() async throws -> ListResources.Result {
        let resources = try await Array(RecentPathsStore.current.read().keys)
            .concurrentFilter {
                try await fileSystem.exists($0)
            }
            .concurrentMap {
                Resource(
                    name: "\($0.basename) graph",
                    uri: "tuist://\($0.pathString)",
                    description: "A graph representing the project \($0.basename)",
                    mimeType: "application/json"
                )
            }
        return ListResources.Result(resources: resources)
    }

    func listTemplates() async throws -> ListResourceTemplates.Result {
        return ListResourceTemplates.Result(templates: [
            Resource.Template(
                uriTemplate: "file:///{path}",
                name: "An Xcode project or workspace",
                description: "Through this template users can read the graph of an Xcode project or workspace to ask questions about it. They need to pass the absolute path to the Xcode project or workspace."
            ),
        ])
    }

    func read(_ resource: ReadResource.Parameters) async throws -> ReadResource.Result {
        let path: AbsolutePath
        if resource.uri.starts(with: "tuist://") {
            path = try AbsolutePath(validating: resource.uri.replacingOccurrences(of: "tuist://", with: ""))
        } else if resource.uri.hasSuffix(".xcodeproj") || resource.uri.hasSuffix(".xcworkspace") {
            path = try AbsolutePath(validating: resource.uri.replacingOccurrences(of: "file://", with: "")).parentDirectory
        } else {
            return ReadResource.Result(contents: [])
        }

        guard try await fileSystem.exists(path) else { return .init(contents: []) }

        let graph: XcodeGraph.Graph
        let config = try await configLoader.loadConfig(path: path)
        if let generatedProjectOptions = config.project.generatedProject {
            (graph, _, _, _) = try await manifestGraphLoader.load(
                path: path,
                disableSandbox: generatedProjectOptions.generationOptions.disableSandbox
            )
        } else {
            graph = try await xcodeGraphMapper.map(at: path)
        }
        let graphJSON = trim(graph: try JSON(data: jsonEncoder.encode(graph))).rawString() ?? ""
        return .init(contents: [.text(graphJSON, uri: resource.uri, mimeType: "application/json")])
    }

    /// Some LLMs have strict limits over the size of the resource, so this function eliminates some of the attributes of the
    /// graph
    /// that increase the size significantly without adding a lot of value to the overall context.
    private func trim(graph: JSON) -> JSON {
        var graph = graph
        graph["projects"] = JSON(graph["projects"].dictionaryValue.mapValues { project in
            var project = project
            project["additionalFiles"] = .null
            project["targets"] = JSON(project["targets"].dictionaryValue.mapValues { target in
                var target = target
                target["sourcesCount"] = JSON(target["sources"].arrayValue.count)
                target["sources"] = .null
                target["resourcesCount"] = JSON(target["resources"]["resources"].arrayValue.count)
                target["resources"] = .null
                target["headers"] = .null
                return target
            })
            return project
        })
        return graph
    }
}
