import Foundation
import RxBlocking
import RxSwift
import TSCBasic
import TuistCache
import TuistCore
import TuistGenerator
import TuistGraph
import TuistLoader
import TuistSupport

protocol FocusServiceProjectGeneratorFactorying {
    func generator(sources: Set<String>, xcframeworks: Bool, cacheProfile: TuistGraph.Cache.Profile, ignoreCache: Bool) -> Generating
}

final class FocusServiceProjectGeneratorFactory: FocusServiceProjectGeneratorFactorying {
    init() {}

    func generator(sources: Set<String>, xcframeworks: Bool, cacheProfile: TuistGraph.Cache.Profile, ignoreCache: Bool) -> Generating {
        let contentHasher = CacheContentHasher()
        let graphMapperProvider = FocusGraphMapperProvider(
            contentHasher: contentHasher,
            cache: !ignoreCache,
            cacheSources: sources,
            cacheProfile: cacheProfile,
            cacheOutputType: xcframeworks ? .xcframework : .framework
        )
        let projectMapperProvider = ProjectMapperProvider(contentHasher: contentHasher)
        return Generator(
            projectMapperProvider: projectMapperProvider,
            graphMapperProvider: graphMapperProvider,
            workspaceMapperProvider: WorkspaceMapperProvider(contentHasher: contentHasher),
            manifestLoaderFactory: ManifestLoaderFactory()
        )
    }
}

final class FocusService {
    private let opener: Opening
    private let projectGeneratorFactory: FocusServiceProjectGeneratorFactorying
    private let configLoader: ConfigLoading

    init(
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: ManifestLoader()),
        opener: Opening = Opener(),
        projectGeneratorFactory: FocusServiceProjectGeneratorFactorying = FocusServiceProjectGeneratorFactory()
    ) {
        self.configLoader = configLoader
        self.opener = opener
        self.projectGeneratorFactory = projectGeneratorFactory
    }

    func run(path: String?, sources: Set<String>, noOpen: Bool, xcframeworks: Bool, profile: String?, ignoreCache: Bool) throws {
        let path = self.path(path)
        let config = try configLoader.loadConfig(path: path)

        let cacheProfile = ignoreCache
            ? CacheProfileResolver.defaultCacheProfileFromTuist
            : try CacheProfileResolver().resolveCacheProfile(named: profile, from: config)

        let generator = projectGeneratorFactory.generator(
            sources: sources,
            xcframeworks: xcframeworks,
            cacheProfile: cacheProfile,
            ignoreCache: ignoreCache
        )
        let workspacePath = try generator.generate(path: path, projectOnly: false)
        if !noOpen {
            try opener.open(path: workspacePath)
        }
    }

    // MARK: - Helpers

    private func path(_ path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
