import DOT
import Foundation
import GraphViz
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
        let manifestGraphLoader = ManifestGraphLoader(manifestLoader: manifestLoader)
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

    func run(format: GraphFormat,
             layoutAlgorithm: GraphViz.LayoutAlgorithm,
             skipTestTargets: Bool,
             skipExternalDependencies: Bool,
             targetsToFilter: [String],
             path: AbsolutePath,
             outputPath: AbsolutePath) throws
    {
        let graph = try manifestGraphLoader.loadGraph(at: path)

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
            let outputGraph = GraphOutput.from(graph)
            try outputGraph.export(to: filePath)
        }

        logger.notice("Graph exported to \(filePath.pathString).", metadata: .success)
    }

    private func export(graph: GraphViz.Graph,
                        at filePath: AbsolutePath,
                        withFormat format: GraphFormat,
                        layoutAlgorithm: LayoutAlgorithm) throws
    {
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

    private func exportPNGRepresentation(from graphVizGraph: GraphViz.Graph,
                                         at filePath: AbsolutePath,
                                         layoutAlgorithm: LayoutAlgorithm) throws
    {
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

extension GraphOutput {
    fileprivate static func from(_ graph: TuistGraph.Graph) -> GraphOutput {
        let projects = graph.projects
            .reduce(into: [String: ProjectOutput]()) { $0[$1.key.pathString] = ProjectOutput.from($1.value) }

        return GraphOutput(name: graph.name, path: graph.path.pathString, projects: projects)
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

extension ProjectOutput {
    fileprivate static func from(_ project: Project) -> ProjectOutput {
        let packages = project.packages.reduce(into: [PackageOutput]()) { $0.append(PackageOutput.from($1)) }
        let schemes = project.schemes.reduce(into: [SchemeOutput]()) { $0.append(SchemeOutput.from($1)) }
        let targets = project.targets.reduce(into: [TargetOutput]()) { $0.append(TargetOutput.from($1)) }

        return ProjectOutput(
            name: project.name,
            path: project.path.pathString,
            packages: packages,
            targets: targets,
            schemes: schemes
        )
    }
}

extension PackageOutput {
    fileprivate static func from(_ package: Package) -> PackageOutput {
        switch package {
        case let .remote(url, _):
            return PackageOutput(kind: PackageOutput.PackageKind.remote, path: url)
        case let .local(path):
            return PackageOutput(kind: PackageOutput.PackageKind.local, path: path.pathString)
        }
    }
}

extension TargetOutput {
    fileprivate static func from(_ target: Target) -> TargetOutput {
        TargetOutput(name: target.name, product: target.product.rawValue)
    }
}

extension SchemeOutput {
    fileprivate static func from(_ scheme: Scheme) -> SchemeOutput {
        var testTargets = [String]()
        if let testAction = scheme.testAction {
            for testTarget in testAction.targets {
                testTargets.append(testTarget.target.name)
            }
        }

        return SchemeOutput(name: scheme.name, testActionTargets: testTargets)
    }
}
