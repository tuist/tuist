import Foundation
import Path
import TuistAlert
import TuistCache
import TuistConfigLoader
import TuistCore
import TuistEnvironment
import TuistLoader
import TuistLogging
import TuistServer
import TuistSupport
import XcodeGraph

struct HashSelectiveTestingCommandService {
    private let generatorFactory: GeneratorFactorying
    private let cacheStorageFactory: CacheStorageFactorying
    private let configLoader: ConfigLoading

    init(
        generatorFactory: GeneratorFactorying,
        cacheStorageFactory: CacheStorageFactorying
    ) {
        self.init(
            generatorFactory: generatorFactory,
            cacheStorageFactory: cacheStorageFactory,
            configLoader: ConfigLoader()
        )
    }

    init(
        generatorFactory: GeneratorFactorying,
        cacheStorageFactory: CacheStorageFactorying,
        configLoader: ConfigLoading
    ) {
        self.generatorFactory = generatorFactory
        self.cacheStorageFactory = cacheStorageFactory
        self.configLoader = configLoader
    }

    func run(path: String?) async throws {
        let absolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: absolutePath)
        // Run the loader through the same generator the test pipeline uses so the
        // graph we hash matches the graph TestsCacheGraphMapper would see at
        // selective-testing fetch time. The previous default-generator path applied
        // a different set of mappers, which silently produced hashes that did not
        // match the ones the cache is keyed on.
        let cacheStorage = try await cacheStorageFactory.cacheLocalStorage()
        let generator = generatorFactory.testing(
            config: config,
            testPlan: nil,
            includedTargets: [],
            excludedTargets: [],
            skipUITests: false,
            skipUnitTests: false,
            configuration: nil,
            ignoreBinaryCache: true,
            ignoreSelectiveTesting: true,
            cacheStorage: cacheStorage,
            destination: nil,
            schemeName: nil
        )
        let (_, environment) = try await generator.loadWithEnvironment(
            path: absolutePath,
            options: config.project.generatedProject?.generationOptions
        )

        let hashesByTarget: [(name: String, hash: String)] = environment.targetTestHashes
            .flatMap { _, targetsByName in
                targetsByName.map { (name: $0.key, hash: $0.value) }
            }
            .sorted { $0.name < $1.name }

        if hashesByTarget.isEmpty {
            AlertController.current.warning(.alert("The project contains no hasheable targets for selective testing."))
        } else {
            for entry in hashesByTarget {
                Logger.current.info("\(entry.name) - \(entry.hash)")
            }
        }
    }
}
