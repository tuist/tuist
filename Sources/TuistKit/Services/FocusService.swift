import Foundation
import RxBlocking
import RxSwift
import TSCBasic
import TuistCache
import TuistCore
import TuistGenerator
import TuistLoader
import TuistSupport

protocol FocusServiceProjectGeneratorProviding {
    func generator(cache: Bool) -> ProjectGenerating
}

final class FocusServiceProjectGeneratorProvider: FocusServiceProjectGeneratorProviding {
    func generator(cache: Bool) -> ProjectGenerating {
        ProjectGenerator(graphMapperProvider: GraphMapperProvider(cache: cache))
    }
}

final class FocusService {
    private let opener: Opening
    private let generatorProvider: FocusServiceProjectGeneratorProviding

    init(opener: Opening = Opener(),
         generatorProvider: FocusServiceProjectGeneratorProviding = FocusServiceProjectGeneratorProvider()) {
        self.opener = opener
        self.generatorProvider = generatorProvider
    }

    func run(cache: Bool) throws {
        let generator = generatorProvider.generator(cache: cache)
        let path = FileHandler.shared.currentPath
        let (workspacePath, _) = try generator.generateProjectWorkspace(path: path)
        try opener.open(path: workspacePath)
    }
}
