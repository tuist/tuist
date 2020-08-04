import TSCBasic
import TuistGenerator
import TuistLoader
import TuistSupport

protocol GenerateServiceProjectGeneratorFactorying {
    func generator(cache: Bool) -> ProjectGenerating
}

final class GenerateServiceProjectGeneratorFactory: GenerateServiceProjectGeneratorFactorying {
    func generator(cache: Bool) -> ProjectGenerating {
        ProjectGenerator(graphMapperProvider: GraphMapperProvider(cache: cache))
    }
}

final class GenerateService {
    // MARK: - Attributes

    private let clock: Clock
    private let projectGeneratorFactory: GenerateServiceProjectGeneratorFactorying

    init(clock: Clock = WallClock(),
         projectGeneratorFactory: GenerateServiceProjectGeneratorFactorying = GenerateServiceProjectGeneratorFactory())
    {
        self.clock = clock
        self.projectGeneratorFactory = projectGeneratorFactory
    }

    func run(path: String?,
             projectOnly: Bool,
             cache: Bool) throws
    {
        let timer = clock.startTimer()
        let path = self.path(path)
        let generator = projectGeneratorFactory.generator(cache: cache)

        _ = try generator.generate(path: path, projectOnly: projectOnly)

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
