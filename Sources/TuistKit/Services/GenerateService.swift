import TSCBasic
import TuistGenerator
import TuistLoader
import TuistSupport

final class GenerateService {
    // MARK: - Attributes

    private let clock: Clock
    private let generator: ProjectGenerating

    init(generator: ProjectGenerating = ProjectGenerator(),
         clock: Clock = WallClock()) {
        self.generator = generator
        self.clock = clock
    }

    func run(path: String?,
             projectOnly: Bool) throws {
        let timer = clock.startTimer()
        let path = self.path(path)

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
