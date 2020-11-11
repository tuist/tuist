import Foundation
import RxBlocking
import RxSwift
import TSCBasic
import TuistCache
import TuistCore
import TuistGenerator
import TuistLoader
import TuistSupport

protocol FocusServiceProjectGeneratorFactorying {
    func generator(sources: Set<String>, xcframeworks: Bool, ignoreCache: Bool) -> Generating
}

final class FocusServiceProjectGeneratorFactory: FocusServiceProjectGeneratorFactorying {
    init() {}

    func generator(sources: Set<String>, xcframeworks: Bool, ignoreCache: Bool) -> Generating {
        let contentHasher = CacheContentHasher()
        let graphMapperProvider = FocusGraphMapperProvider(contentHasher: contentHasher,
                                                           cache: !ignoreCache,
                                                           cacheSources: sources,
                                                           cacheOutputType: xcframeworks ? .xcframework : .framework)
        let projectMapperProvider = ProjectMapperProvider(contentHasher: contentHasher)
        return Generator(projectMapperProvider: projectMapperProvider,
                         graphMapperProvider: graphMapperProvider,
                         workspaceMapperProvider: WorkspaceMapperProvider(contentHasher: contentHasher),
                         manifestLoaderFactory: ManifestLoaderFactory())
    }
}

final class FocusService {
    private let opener: Opening
    private let projectGeneratorFactory: FocusServiceProjectGeneratorFactorying
    private let manifestLoader: ManifestLoading

    init(manifestLoader: ManifestLoading = ManifestLoader(),
         opener: Opening = Opener(),
         projectGeneratorFactory: FocusServiceProjectGeneratorFactorying = FocusServiceProjectGeneratorFactory())
    {
        self.manifestLoader = manifestLoader
        self.opener = opener
        self.projectGeneratorFactory = projectGeneratorFactory
    }

    func run(path: String?, sources: Set<String>, noOpen: Bool, xcframeworks: Bool, ignoreCache: Bool) throws {
        let path = self.path(path)
        let generator = projectGeneratorFactory.generator(sources: sources,
                                                          xcframeworks: xcframeworks,
                                                          ignoreCache: ignoreCache)
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
