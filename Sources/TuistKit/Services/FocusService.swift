import Foundation
import TSCBasic
import TuistCache
import TuistCore
import TuistGenerator
import TuistGraph
import TuistLoader
import TuistPlugin
import TuistSupport

final class FocusService {
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

    func run(path: String?, sources: Set<String>, noOpen: Bool, xcframeworks: Bool, profile: String?, ignoreCache: Bool) throws {
        let timer = clock.startTimer()
        let path = self.path(path)
        let config = try configLoader.loadConfig(path: path)
        let cacheProfile = try CacheProfileResolver().resolveCacheProfile(named: profile, from: config)
        let generator = generatorFactory.focus(
            config: config,
            sources: sources.isEmpty ? try projectTargets(at: path, config: config) : sources,
            xcframeworks: xcframeworks,
            cacheProfile: cacheProfile,
            ignoreCache: ignoreCache
        )
        let workspacePath = try generator.generate(path: path, projectOnly: false)
        if !noOpen {
            try opener.open(path: workspacePath)
        }
        logger.notice("Project generated.", metadata: .success)
        logger.notice(timeTakenLoggerFormatter.timeTakenMessage(for: timer))
    }

    // MARK: - Helpers

    private func path(_ path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    private func projectTargets(at path: AbsolutePath, config: Config) throws -> Set<String> {
        let plugins = try pluginService.loadPlugins(using: config)
        try manifestLoader.register(plugins: plugins)
        let projects: [AbsolutePath]
        if let workspace = try? manifestLoader.loadWorkspace(at: path) {
            projects = workspace.projects.map { AbsolutePath(path, .init($0.pathString)) }
        } else {
            projects = [path]
        }

        return try Set(projects.flatMap { try manifestLoader.loadProject(at: $0).targets.map(\.name) })
    }
}
