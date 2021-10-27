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
import Signals

protocol PlayServiceProjectGeneratorFactorying {
    func generator(sources: Set<String>, xcframeworks: Bool, cacheProfile: TuistGraph.Cache.Profile, ignoreCache: Bool, temporaryDirectory: AbsolutePath) -> Generating
}

final class PlayServiceProjectGeneratorFactory: PlayServiceProjectGeneratorFactorying {
    init() {}

    func generator(sources: Set<String>, xcframeworks: Bool, cacheProfile: TuistGraph.Cache.Profile, ignoreCache: Bool, temporaryDirectory: AbsolutePath) -> Generating {
        let contentHasher = CacheContentHasher()
        let focusGraphMapperProvider = FocusGraphMapperProvider(
            contentHasher: contentHasher,
            cache: !ignoreCache,
            cacheSources: sources,
            cacheProfile: cacheProfile,
            cacheOutputType: xcframeworks ? .xcframework : .framework
        )
        // TODO: Add support for multiple targets
        let graphMapperProvider = PlayGraphMapperProvider(targetName: sources.first!, temporaryDirectory: temporaryDirectory, focusGraphMapperProvider: focusGraphMapperProvider)
        let projectMapperProvider = ProjectMapperProvider(contentHasher: contentHasher)
        return Generator(
            projectMapperProvider: projectMapperProvider,
            graphMapperProvider: graphMapperProvider,
            workspaceMapperProvider: WorkspaceMapperProvider(contentHasher: contentHasher),
            manifestLoaderFactory: ManifestLoaderFactory()
        )
    }
}

final class PlayService {
    private let opener: Opening
    private let projectGeneratorFactory: PlayServiceProjectGeneratorFactorying
    private let configLoader: ConfigLoading
    private static var temporaryDirectory: AbsolutePath?

    init(
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: ManifestLoader()),
        opener: Opening = Opener(),
        projectGeneratorFactory: PlayServiceProjectGeneratorFactorying = PlayServiceProjectGeneratorFactory()
    ) {
        self.configLoader = configLoader
        self.opener = opener
        self.projectGeneratorFactory = projectGeneratorFactory
    }

    func run(path: String?, sources: Set<String>, xcframeworks: Bool, profile: String?, ignoreCache: Bool) throws {
        // tuist inspect MyTarget
        
        // - 3 direct dependencies
        // - X source files
        // - 4 transitive dependencies
        
        
        
        // TODO: Generate the project in a temporary directory
        // TODO: Include a playground in a temporary directory
        // TODO: Adjust the cache mapping to include a binary for the given target
        // Playground.playground/
        //   Contents.swift
        //   contents.xcplayground
        //        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        //        <playground version='5.0' target-platform='ios' buildActiveScheme='true' executeOnSourceChanges='false' importAppTypes='true'>
        //            <timeline fileName='timeline.xctimeline'/>
        //        </playground>
    
        let path = self.path(path)
        let config = try configLoader.loadConfig(path: path)

        let cacheProfile = try CacheProfileResolver().resolveCacheProfile(named: profile, from: config)
        
        try FileHandler.shared.inTemporaryDirectory { temporaryDirectory in
            let generator = projectGeneratorFactory.generator(
                sources: sources,
                xcframeworks: xcframeworks,
                cacheProfile: cacheProfile,
                ignoreCache: ignoreCache,
                temporaryDirectory: temporaryDirectory
            )
            
            let workspacePath = try generator.generate(path: path, projectOnly: false)
            PlayService.temporaryDirectory = temporaryDirectory
            
            guard let selectedXcode = try XcodeController.shared.selected() else {
                throw EditServiceError.xcodeNotSelected
            }
            
            Signals.trap(signals: [.int, .abrt]) { _ in
                // swiftlint:disable:next force_try
                try! PlayService.temporaryDirectory.map(FileHandler.shared.delete)
                exit(0)
            }

            try opener.open(path: workspacePath, application: selectedXcode.path, wait: true)
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
