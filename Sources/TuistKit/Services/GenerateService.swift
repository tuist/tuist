import TSCBasic
import TuistGenerator
import TuistLoader
import TuistSupport

protocol GenerateServiceProjectGeneratorFactorying {
    func generator(cache: Bool, includeSources: Set<String>) -> ProjectGenerating
}

final class GenerateServiceProjectGeneratorFactory: GenerateServiceProjectGeneratorFactorying {
    func generator(cache: Bool, includeSources: Set<String>) -> ProjectGenerating {
        ProjectGenerator(graphMapperProvider: GraphMapperProvider(cache: cache, includeSources: includeSources))
    }
}

final class GenerateService {
    // MARK: - Attributes

    private let opener: Opening
    private let clock: Clock
    private let projectGeneratorFactory: GenerateServiceProjectGeneratorFactorying

    // MARK: - Init

    init(clock: Clock = WallClock(),
         opener: Opening = Opener(),
         projectGeneratorFactory: GenerateServiceProjectGeneratorFactorying = GenerateServiceProjectGeneratorFactory())
    {
        self.clock = clock
        self.opener = opener
        self.projectGeneratorFactory = projectGeneratorFactory
    }

    func run(path: String?,
             projectOnly: Bool,
             cache: Bool,
             cacheSources: Set<String>,
             open: Bool) throws
    {
        let timer = clock.startTimer()
        let path = self.path(path)
        let generator = projectGeneratorFactory.generator(cache: cache, includeSources: cacheSources)

        let generatedProjectPath = try generator.generate(path: path, projectOnly: projectOnly)
        if open {
            try opener.open(path: generatedProjectPath, wait: false)
        }

        let time = String(format: "%.3f", timer.stop())

        logger.notice("Project generated.", metadata: .success)
        logger.notice("Total time taken: \(time)s")
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
