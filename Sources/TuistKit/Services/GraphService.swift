import DOT
import Foundation
import GraphViz
import ProjectAutomation
import TSCBasic
import TuistCore
import TuistGenerator
import TuistGraph
import TuistLoader
import TuistPlugin
import TuistSupport

final class GraphService {
    private let graphVizMapper: GraphToGraphVizMapping
    private let manifestGraphLoader: ManifestGraphLoading

    convenience init() {
        let manifestLoader = ManifestLoaderFactory()
            .createManifestLoader()
        let manifestGraphLoader = ManifestGraphLoader(
            manifestLoader: manifestLoader,
            workspaceMapper: SequentialWorkspaceMapper(mappers: []),
            graphMapper: SequentialGraphMapper([])
        )
        let graphVizMapper = GraphToGraphVizMapper()
        self.init(
            graphVizGenerator: graphVizMapper,
            manifestGraphLoader: manifestGraphLoader
        )
    }

    init(
        graphVizGenerator: GraphToGraphVizMapping,
        manifestGraphLoader: ManifestGraphLoading
    ) {
        graphVizMapper = graphVizGenerator
        self.manifestGraphLoader = manifestGraphLoader
    }

    func run(
        format: GraphFormat,
        layoutAlgorithm: GraphViz.LayoutAlgorithm,
        skipTestTargets: Bool,
        skipExternalDependencies: Bool,
        targetsToFilter: [String],
        path: AbsolutePath,
        outputPath: AbsolutePath
    ) async throws {
        let (graph, _) = try await manifestGraphLoader.load(path: path)

        let filePath = outputPath.appending(component: "graph.\(format.rawValue)")
        if FileHandler.shared.exists(filePath) {
            logger.notice("Deleting existing graph at \(filePath.pathString)")
            try FileHandler.shared.delete(filePath)
        }

        switch format {
        case .dot, .png:
            let graphVizGraph = graphVizMapper.map(
                graph: graph,
                skipTestTargets: skipTestTargets,
                skipExternalDependencies: skipExternalDependencies,
                targetsToFilter: targetsToFilter
            )

            try export(graph: graphVizGraph, at: filePath, withFormat: format, layoutAlgorithm: layoutAlgorithm)
        case .json:
            let outputGraph = ProjectAutomation.Graph.from(graph)
            try outputGraph.export(to: filePath)
        }

        logger.notice("Graph exported to \(filePath.pathString).", metadata: .success)
    }

    private func export(
        graph: GraphViz.Graph,
        at filePath: AbsolutePath,
        withFormat format: GraphFormat,
        layoutAlgorithm: LayoutAlgorithm
    ) throws {
        switch format {
        case .dot:
            try exportDOTRepresentation(from: graph, at: filePath)
        case .png:
            try exportPNGRepresentation(from: graph, at: filePath, layoutAlgorithm: layoutAlgorithm)
        case .json:
            throw GraphServiceError.jsonNotValidForVisualExport
        }
    }

    private func exportDOTRepresentation(from graphVizGraph: GraphViz.Graph, at filePath: AbsolutePath) throws {
        let dotFile = DOTEncoder().encode(graphVizGraph)
        try FileHandler.shared.write(dotFile, path: filePath, atomically: true)
    }

    private func exportPNGRepresentation(
        from graphVizGraph: GraphViz.Graph,
        at filePath: AbsolutePath,
        layoutAlgorithm: LayoutAlgorithm
    ) throws {
        if try !isGraphVizInstalled() {
            try installGraphViz()
        }
        let data = try graphVizGraph.render(using: layoutAlgorithm, to: .png)
        FileManager.default.createFile(atPath: filePath.pathString, contents: data, attributes: nil)
        try System.shared.async(["open", filePath.pathString])
    }

    private func isGraphVizInstalled() throws -> Bool {
        try System.shared.capture(["brew", "list", "--formula"]).contains("graphviz")
    }

    private func installGraphViz() throws {
        logger.notice("Installing GraphViz...")
        var env = System.shared.env
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        try System.shared.runAndPrint(["brew", "install", "graphviz"], verbose: false, environment: env)
    }
}

private enum GraphServiceError: FatalError {
    case jsonNotValidForVisualExport
    case encodingError(String)

    var description: String {
        switch self {
        case .jsonNotValidForVisualExport:
            return "json format is not valid for visual export"
        case let .encodingError(format):
            return "failed to encode graph to \(format)"
        }
    }

    var type: ErrorType {
        switch self {
        case .jsonNotValidForVisualExport:
            return .abort
        case .encodingError:
            return .abort
        }
    }
}

extension ProjectAutomation.Graph {
    fileprivate static func from(_ graph: TuistGraph.Graph) -> ProjectAutomation.Graph {
        let projects = graph.projects.reduce(
            into: [String: ProjectAutomation.Project]()
        ) {
            $0[$1.key.pathString] = ProjectAutomation.Project.from($1.value)
        }

        return ProjectAutomation.Graph(name: graph.name, path: graph.path.pathString, projects: projects)
    }

    fileprivate func export(to filePath: AbsolutePath) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        let jsonData = try encoder.encode(self)
        let jsonString = String(data: jsonData, encoding: .utf8)
        guard let jsonString = jsonString else {
            throw GraphServiceError.encodingError(GraphFormat.json.rawValue)
        }

        try FileHandler.shared.write(jsonString, path: filePath, atomically: true)
    }
}

extension ProjectAutomation.Project {
    fileprivate static func from(_ project: TuistGraph.Project) -> ProjectAutomation.Project {
        let packages = project.packages
            .reduce(into: [ProjectAutomation.Package]()) { $0.append(ProjectAutomation.Package.from($1)) }
        let schemes = project.schemes.reduce(into: [ProjectAutomation.Scheme]()) { $0.append(ProjectAutomation.Scheme.from($1)) }
        let targets = project.targets.reduce(into: [ProjectAutomation.Target]()) { $0.append(ProjectAutomation.Target.from($1)) }

        return ProjectAutomation.Project(
            name: project.name,
            path: project.path.pathString,
            isExternal: project.isExternal,
            packages: packages,
            targets: targets,
            schemes: schemes
        )
    }
}

extension ProjectAutomation.Package {
    fileprivate static func from(_ package: TuistGraph.Package) -> ProjectAutomation.Package {
        switch package {
        case let .remote(url, _):
            return ProjectAutomation.Package(kind: ProjectAutomation.Package.PackageKind.remote, path: url)
        case let .local(path):
            return ProjectAutomation.Package(kind: ProjectAutomation.Package.PackageKind.local, path: path.pathString)
        }
    }
}

extension ProjectAutomation.Target {
    fileprivate static func from(_ target: TuistGraph.Target) -> ProjectAutomation.Target {
        ProjectAutomation.Target(
            name: target.name,
            product: target.product.rawValue,
            sources: target.sources.map(\.path.pathString)
        )
    }
}

extension ProjectAutomation.Scheme {
    fileprivate static func from(_ scheme: TuistGraph.Scheme) -> ProjectAutomation.Scheme {
        var testTargets = [String]()
        if let testAction = scheme.testAction {
            for testTarget in testAction.targets {
                testTargets.append(testTarget.target.name)
            }
        }

        return ProjectAutomation.Scheme(name: scheme.name, testActionTargets: testTargets)
    }
}
