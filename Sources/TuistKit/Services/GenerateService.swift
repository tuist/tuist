import Foundation
import Path
import TuistCore
import TuistGenerator
import TuistLoader
import TuistPlugin
import TuistServer
import TuistSupport
import XcodeGraph

final class GenerateService {
    private let opener: Opening
    private let clock: Clock
    private let timeTakenLoggerFormatter: TimeTakenLoggerFormatting
    private let cacheStorageFactory: CacheStorageFactorying
    private let generatorFactory: GeneratorFactorying
    private let manifestLoader: ManifestLoading
    private let pluginService: PluginServicing
    private let configLoader: ConfigLoading

    init(
        cacheStorageFactory: CacheStorageFactorying,
        generatorFactory: GeneratorFactorying,
        clock: Clock = WallClock(),
        timeTakenLoggerFormatter: TimeTakenLoggerFormatting = TimeTakenLoggerFormatter(),
        manifestLoader: ManifestLoading = ManifestLoader(),
        opener: Opening = Opener(),
        pluginService: PluginServicing = PluginService(),
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: ManifestLoader())
    ) {
        self.generatorFactory = generatorFactory
        self.cacheStorageFactory = cacheStorageFactory
        self.clock = clock
        self.timeTakenLoggerFormatter = timeTakenLoggerFormatter
        self.manifestLoader = manifestLoader
        self.opener = opener
        self.pluginService = pluginService
        self.configLoader = configLoader
    }

    func run(
        path: String?,
        sources: Set<String>,
        noOpen: Bool,
        configuration: String?,
        ignoreBinaryCache: Bool
    ) async throws {
        let timer = clock.startTimer()
        let path = try self.path(path)
        let config = try await configLoader.loadConfig(path: path)
        let cacheStorage = try cacheStorageFactory.cacheStorage(config: config)
        let generator = generatorFactory.generation(
            config: config,
            sources: sources,
            configuration: configuration,
            ignoreBinaryCache: ignoreBinaryCache,
            cacheStorage: cacheStorage
        )
        let workspacePath = try await generator.generate(path: path)
        if !noOpen {
            try opener.open(path: workspacePath)
        }
        logger.notice("Project generated.", metadata: .success)
        logger.notice(timeTakenLoggerFormatter.timeTakenMessage(for: timer))
    }

    // MARK: - Helpers

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
