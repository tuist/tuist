import Foundation
import Path
import TuistCache
import TuistCore
import TuistHasher
import TuistLoader
import TuistSupport
import XcodeGraph
import XcodeGraphMapper

final class HashSelectiveTestingCommandService {
    private let generatorFactory: GeneratorFactorying
    private let configLoader: ConfigLoading
    private let manifestLoader: ManifestLoading
    private let manifestGraphLoader: ManifestGraphLoading
    private let xcodeGraphMapper: XcodeGraphMapping
    private let selectiveTestingGraphHasher: SelectiveTestingGraphHashing

    convenience init(selectiveTestingGraphHasher: SelectiveTestingGraphHashing) {
        let generatorFactory = GeneratorFactory()
        let manifestLoader = ManifestLoaderFactory()
            .createManifestLoader()
        let manifestGraphLoader = ManifestGraphLoader(
            manifestLoader: manifestLoader,
            workspaceMapper: SequentialWorkspaceMapper(mappers: []),
            graphMapper: SequentialGraphMapper([])
        )
        self.init(
            generatorFactory: generatorFactory,
            configLoader: ConfigLoader(manifestLoader: ManifestLoader()),
            manifestLoader: manifestLoader,
            manifestGraphLoader: manifestGraphLoader,
            xcodeGraphMapper: XcodeGraphMapper(),
            selectiveTestingGraphHasher: selectiveTestingGraphHasher
        )
    }

    init(
        generatorFactory: GeneratorFactorying,
        configLoader: ConfigLoading,
        manifestLoader: ManifestLoading,
        manifestGraphLoader: ManifestGraphLoading,
        xcodeGraphMapper: XcodeGraphMapping,
        selectiveTestingGraphHasher: SelectiveTestingGraphHashing
    ) {
        self.generatorFactory = generatorFactory
        self.configLoader = configLoader
        self.manifestLoader = manifestLoader
        self.manifestGraphLoader = manifestGraphLoader
        self.xcodeGraphMapper = xcodeGraphMapper
        self.selectiveTestingGraphHasher = selectiveTestingGraphHasher
    }

    private func absolutePath(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    func run(
        path: String?,
        passthroughXcodebuildArguments: [String]
    ) async throws {
        let absolutePath = try absolutePath(path)

        let graph: XcodeGraph.Graph

        if try await manifestLoader.hasRootManifest(at: absolutePath) {
            let config = try await configLoader.loadConfig(path: absolutePath)
            let generator = generatorFactory.defaultGenerator(config: config, includedTargets: [])
            graph = try await generator.load(
                path: absolutePath,
                options: config.project.generatedProject?.generationOptions
            )
        } else {
            graph = try await xcodeGraphMapper.map(at: absolutePath)
        }

        let hashes = try await selectiveTestingGraphHasher.hash(
            graph: graph,
            additionalStrings: XcodeBuildTestCommandService
                .additionalHashableStringsFromXcodebuildPassthroughArguments(passthroughXcodebuildArguments)
        )

        let sortedHashes = hashes.sorted { $0.key.target.name < $1.key.target.name }

        if sortedHashes.isEmpty {
            AlertController.current.warning(.alert("The project contains no hasheable targets for selective testing."))
        } else {
            for (target, targetContentHash) in sortedHashes {
                Logger.current.info("\(target.target.name) - \(targetContentHash.hash)")
            }
        }
    }
}
