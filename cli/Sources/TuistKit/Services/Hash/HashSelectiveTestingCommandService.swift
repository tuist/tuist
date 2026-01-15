import Foundation
import Path
import TuistCache
import TuistCore
import TuistHasher
import TuistLoader
import TuistSupport
import XcodeGraph

final class HashSelectiveTestingCommandService {
    private let generatorFactory: GeneratorFactorying
    private let configLoader: ConfigLoading
    private let selectiveTestingGraphHasher: SelectiveTestingGraphHashing

    convenience init(selectiveTestingGraphHasher: SelectiveTestingGraphHashing) {
        self.init(
            generatorFactory: GeneratorFactory(),
            configLoader: ConfigLoader(),
            selectiveTestingGraphHasher: selectiveTestingGraphHasher
        )
    }

    init(
        generatorFactory: GeneratorFactorying,
        configLoader: ConfigLoading,
        selectiveTestingGraphHasher: SelectiveTestingGraphHashing
    ) {
        self.generatorFactory = generatorFactory
        self.configLoader = configLoader
        self.selectiveTestingGraphHasher = selectiveTestingGraphHasher
    }

    private func absolutePath(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    func run(path: String?) async throws {
        let absolutePath = try absolutePath(path)

        let config = try await configLoader.loadConfig(path: absolutePath)
        let generator = generatorFactory.defaultGenerator(config: config, includedTargets: [])
        let graph = try await generator.load(
            path: absolutePath,
            options: config.project.generatedProject?.generationOptions
        )

        let hashes = try await selectiveTestingGraphHasher.hash(
            graph: graph,
            additionalStrings: []
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
