import TSCBasic
import TuistCache
import TuistCore
import TuistGenerator
import TuistLoader
import TuistSupport

final class GenerateService {
    // MARK: - Attributes

    private let opener: Opening
    private let clock: Clock
    private let timeTakenLoggerFormatter: TimeTakenLoggerFormatting
    private let generatorFactory: GeneratorFactorying
    private let configLoader: ConfigLoading

    // MARK: - Init

    init(clock: Clock = WallClock(),
         timeTakenLoggerFormatter: TimeTakenLoggerFormatting = TimeTakenLoggerFormatter(),
         opener: Opening = Opener(),
         generatorFactory: GeneratorFactorying = GeneratorFactory(),
         configLoader: ConfigLoading = ConfigLoader(manifestLoader: ManifestLoader()))
    {
        self.clock = clock
        self.timeTakenLoggerFormatter = timeTakenLoggerFormatter
        self.opener = opener
        self.generatorFactory = generatorFactory
        self.configLoader = configLoader
    }

    func run(path: String?,
             projectOnly: Bool,
             open: Bool) async throws
    {
        let timer = clock.startTimer()
        let path = self.path(path)
        let config = try configLoader.loadConfig(path: path)
        let generator = generatorFactory.default(config: config)

        let generatedProjectPath = try await generator.generate(path: path, projectOnly: projectOnly)
        if open {
            try opener.open(path: generatedProjectPath, wait: false)
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
}
