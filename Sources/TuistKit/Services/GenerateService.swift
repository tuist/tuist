import Foundation
import Path
import TuistCache
import TuistCore
import TuistGenerator
import TuistLoader
import TuistPlugin
import TuistServer
import TuistSupport
import XcodeGraph
import ServiceContextModule

final class GenerateService {
    private let opener: Opening
    private let clock: Clock
    private let timeTakenLoggerFormatter: TimeTakenLoggerFormatting
    private let cacheStorageFactory: CacheStorageFactorying
    private let generatorFactory: GeneratorFactorying
    private let pluginService: PluginServicing
    private let configLoader: ConfigLoading

    init(
        cacheStorageFactory: CacheStorageFactorying,
        generatorFactory: GeneratorFactorying,
        clock: Clock = WallClock(),
        timeTakenLoggerFormatter: TimeTakenLoggerFormatting = TimeTakenLoggerFormatter(),
        opener: Opening = Opener(),
        pluginService: PluginServicing = PluginService(),
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: ManifestLoader(), warningController: WarningController.shared)
    ) {
        self.generatorFactory = generatorFactory
        self.cacheStorageFactory = cacheStorageFactory
        self.clock = clock
        self.timeTakenLoggerFormatter = timeTakenLoggerFormatter
        self.opener = opener
        self.pluginService = pluginService
        self.configLoader = configLoader
    }

    func run(
        path: String?,
        sources: Set<String>,
        noOpen: Bool,
        configuration: String?,
        ignoreBinaryCache: Bool,
        analyticsDelegate: TrackableParametersDelegate?
    ) async throws {
        let timer = clock.startTimer()
        let path = try self.path(path)
        let config = try await configLoader.loadConfig(path: path)
        let cacheStorage = try await cacheStorageFactory.cacheStorage(config: config)
        let generator = generatorFactory.generation(
            config: config,
            sources: sources,
            configuration: configuration,
            ignoreBinaryCache: ignoreBinaryCache,
            cacheStorage: cacheStorage
        )
        let (workspacePath, _, environment) = try await generator.generateWithGraph(path: path)
        analyticsDelegate?.cacheableTargets = environment.cacheableTargets
        analyticsDelegate?.cacheItems = environment.targetCacheItems.values.flatMap(\.values)
            .sorted(by: { $0.name < $1.name })
        if !noOpen {
            try await opener.open(path: workspacePath)
        }
        ServiceContext.$current.get()?.logger?.notice("Project generated.", metadata: .success)
        ServiceContext.$current.get()?.logger?.notice(timeTakenLoggerFormatter.timeTakenMessage(for: timer))
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
