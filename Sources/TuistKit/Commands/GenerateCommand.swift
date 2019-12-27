import Basic
import Foundation
import SPMUtility
import TuistGenerator
import TuistLoader
import TuistSupport

class GenerateCommand: NSObject, Command {
    // MARK: - Static

    static let command = "generate"
    static let overview = "Generates an Xcode workspace to start working on the project."

    // MARK: - Attributes

    private let generator: Generating
    private let manifestLoader: ManifestLoading
    private let clock: Clock
    let pathArgument: OptionArgument<String>
    let projectOnlyArgument: OptionArgument<Bool>

    // MARK: - Init

    required convenience init(parser: ArgumentParser) {
        let manifestLoader = ManifestLoader()
        let manifestLinter = ManifestLinter()
        let modelLoader = GeneratorModelLoader(manifestLoader: manifestLoader, manifestLinter: manifestLinter)
        let generator = Generator(modelLoader: modelLoader)
        self.init(parser: parser,
                  generator: generator,
                  manifestLoader: manifestLoader,
                  clock: WallClock())
    }

    init(parser: ArgumentParser,
         generator: Generating,
         manifestLoader: ManifestLoading,
         clock: Clock) {
        let subParser = parser.add(subparser: GenerateCommand.command, overview: GenerateCommand.overview)
        self.generator = generator
        self.manifestLoader = manifestLoader
        self.clock = clock

        pathArgument = subParser.add(option: "--path",
                                     shortName: "-p",
                                     kind: String.self,
                                     usage: "The path where the project will be generated.",
                                     completion: .filename)

        projectOnlyArgument = subParser.add(option: "--project-only",
                                            kind: Bool.self,
                                            usage: "Only generate the local project (without generating its dependencies).")
    }

    func run(with arguments: ArgumentParser.Result) throws {
        let timer = clock.startTimer()
        let path = self.path(arguments: arguments)
        let projectOnly = arguments.get(projectOnlyArgument) ?? false

        _ = try generator.generate(at: path,
                                   manifestLoader: manifestLoader,
                                   projectOnly: projectOnly)

        let time = String(format: "%.3f", timer.stop())
        Printer.shared.print(success: "Project generated.")
        Printer.shared.print("Total time taken: \(time)s")
    }

    // MARK: - Fileprivate

    private func path(arguments: ArgumentParser.Result) -> AbsolutePath {
        if let path = arguments.get(pathArgument) {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
