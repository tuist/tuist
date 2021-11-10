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

final class FocusService {
    private let opener: Opening
    private let generatorFactory: GeneratorFactorying
    private let configLoader: ConfigLoading

    init(
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: ManifestLoader()),
        opener: Opening = Opener(),
        generatorFactory: GeneratorFactorying = GeneratorFactory()
    ) {
        self.configLoader = configLoader
        self.opener = opener
        self.generatorFactory = generatorFactory
    }

    func run(path: String?, sources: Set<String>, noOpen: Bool, xcframeworks: Bool, profile: String?, ignoreCache: Bool) throws {
        let path = self.path(path)
        let config = try configLoader.loadConfig(path: path)
        let cacheProfile = try CacheProfileResolver().resolveCacheProfile(named: profile, from: config)
        let generator = generatorFactory.focus(
            config: config,
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
