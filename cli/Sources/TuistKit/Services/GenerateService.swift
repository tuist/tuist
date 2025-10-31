import Foundation
import Path
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
        includedTargets: Set<TargetQuery>,
        noOpen: Bool,
        configuration: String?,
        ignoreBinaryCache: Bool,
        cacheProfile: CacheProfileType?
    ) async throws {
        let timer = clock.startTimer()
        let path = try self.path(path)
        let config = try await configLoader.loadConfig(path: path)
            .assertingIsGeneratedProjectOrSwiftPackage(
                errorMessageOverride:
                "The 'tuist generate' command is only available for generated projects and Swift packages."
            )
        let cacheStorage = try await cacheStorageFactory.cacheStorage(config: config)

        let resolvedCacheProfile = try config.resolveCacheProfile(
            ignoreBinaryCache: ignoreBinaryCache,
            includedTargets: includedTargets,
            cacheProfile: cacheProfile
        )

        let generator = generatorFactory.generation(
            config: config,
            includedTargets: includedTargets,
            configuration: configuration,
            cacheProfile: resolvedCacheProfile,
            cacheStorage: cacheStorage
        )
        let (workspacePath, _, _) = try await generator.generateWithGraph(
            path: path,
            options: config.project.generatedProject?.generationOptions
        )
        if !noOpen {
            try await opener.open(path: workspacePath)
        }
        AlertController.current.success(.alert("Project generated."))
        Logger.current.notice(timeTakenLoggerFormatter.timeTakenMessage(for: timer))
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
