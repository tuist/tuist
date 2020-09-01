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
    func generator(cache: Bool, includeSources: Set<String>) -> ProjectGenerating
}

final class FocusServiceProjectGeneratorFactory: FocusServiceProjectGeneratorFactorying {
    func generator(cache: Bool, includeSources: Set<String>) -> ProjectGenerating {
        ProjectGenerator(graphMapperProvider: GraphMapperProvider(cache: cache, includeSources: includeSources))
    }
}

enum FocusServiceError: FatalError {
    case cacheWorkspaceNonSupported
    var description: String {
        switch self {
        case .cacheWorkspaceNonSupported:
            return "Caching is only supported when focusing on a project. Please, run the command in a directory that contains a Project.swift file."
        }
    }

    var type: ErrorType {
        switch self {
        case .cacheWorkspaceNonSupported:
            return .abort
        }
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

    func run(cache: Bool, path: String?, includeSources: Set<String>, noOpen: Bool) throws {
        let path = self.path(path)
        if isWorkspace(path: path), cache {
            throw FocusServiceError.cacheWorkspaceNonSupported
        }
        let generator = projectGeneratorFactory.generator(cache: cache, includeSources: includeSources)
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

    private func isWorkspace(path: AbsolutePath) -> Bool {
        manifestLoader.manifests(at: path).contains(.workspace)
    }
}
