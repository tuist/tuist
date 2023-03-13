import Foundation
import TSCBasic
import TuistCache
import TuistCore
import TuistGenerator
import TuistGraph
import TuistLoader
import TuistPlugin
import TuistSupport

final class GenerateService {
    private let opener: Opening
    private let clock: Clock
    private let timeTakenLoggerFormatter: TimeTakenLoggerFormatting
    private let generatorFactory: GeneratorFactorying
    private let configLoader: ConfigLoading
    private let manifestLoader: ManifestLoading
    private let pluginService: PluginServicing

    init(
        clock: Clock = WallClock(),
        timeTakenLoggerFormatter: TimeTakenLoggerFormatting = TimeTakenLoggerFormatter(),
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: ManifestLoader()),
        manifestLoader: ManifestLoading = ManifestLoader(),
        opener: Opening = Opener(),
        generatorFactory: GeneratorFactorying = GeneratorFactory(),
        pluginService: PluginServicing = PluginService()
    ) {
        self.clock = clock
        self.timeTakenLoggerFormatter = timeTakenLoggerFormatter
        self.configLoader = configLoader
        self.manifestLoader = manifestLoader
        self.opener = opener
        self.generatorFactory = generatorFactory
        self.pluginService = pluginService
    }

    func run(
        path: String?,
        sources: Set<String>,
        noOpen: Bool,
        xcframeworks: Bool,
        destination: CacheXCFrameworkDestination,
        profile: String?,
        ignoreCache: Bool
    ) async throws {
        let timer = clock.startTimer()
        let path = try self.path(path)
        let config = try configLoader.loadConfig(path: path)
        let cacheProfile = try CacheProfileResolver().resolveCacheProfile(named: profile, from: config)
        let cacheOutputType: CacheOutputType = xcframeworks ? .xcframework(destination) : .framework
        let generator = generatorFactory.focus(
            config: config,
            sources: sources,
            cacheOutputType: cacheOutputType,
            cacheProfile: cacheProfile,
            ignoreCache: ignoreCache
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
        if let path = path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
