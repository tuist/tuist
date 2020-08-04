import Foundation
import TSCBasic
import TuistGenerator
import TuistLoader
import TuistSupport

final class GraphService {
    /// Dot graph generator.
    private let dotGraphGenerator: DotGraphGenerating

    /// Manifest loader.
    private let manifestLoader: ManifestLoading

    init(dotGraphGenerator: DotGraphGenerating = DotGraphGenerator(modelLoader: GeneratorModelLoader(manifestLoader: ManifestLoader(),
                                                                                                     manifestLinter: ManifestLinter())),
    manifestLoader: ManifestLoading = ManifestLoader()) {
        self.dotGraphGenerator = dotGraphGenerator
        self.manifestLoader = manifestLoader
    }

    func run(skipTestTargets: Bool, skipExternalDependencies: Bool) throws {
        let graph = try dotGraphGenerator.generate(at: FileHandler.shared.currentPath,
                                                   manifestLoader: manifestLoader,
                                                   skipTestTargets: skipTestTargets,
                                                   skipExternalDependencies: skipExternalDependencies)

        let path = FileHandler.shared.currentPath.appending(component: "graph.dot")
        if FileHandler.shared.exists(path) {
            logger.notice("Deleting existing graph at \(path.pathString)")
            try FileHandler.shared.delete(path)
        }

        try FileHandler.shared.write(graph, path: path, atomically: true)
        logger.notice("Graph exported to \(path.pathString)", metadata: .success)
    }
}
