import Foundation
import Path
import ServiceContextModule
import TuistCache
import TuistCore
import TuistGenerator
import TuistLoader
import TuistPlugin
import TuistServer
import TuistSupport

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
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: ManifestLoader())
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
        ignoreBinaryCache: Bool
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
        if !noOpen {
            try await opener.open(path: workspacePath)
        }
        ServiceContext.current?.alerts?.append(.success(.alert("Project generated.")))
        ServiceContext.current?.logger?.notice(timeTakenLoggerFormatter.timeTakenMessage(for: timer))
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
