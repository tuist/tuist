import Basic
import Foundation
import SPMUtility
import TuistCore
import TuistGenerator

class GenerateCommand: NSObject, Command {
    // MARK: - Static

    static let command = "generate"
    static let overview = "Generates an Xcode workspace to start working on the project."

    // MARK: - Attributes

    private let generator: Generating
    private let manifestLoader: GraphManifestLoading
    private let clock: Clock
    
    let pathArgument: OptionArgument<String>
    let projectOnlyArgument: OptionArgument<Bool>
    let carthageProjectsArgument: OptionArgument<Bool>
    let verboseArgument: OptionArgument<Bool>

    // MARK: - Init

    required convenience init(parser: ArgumentParser) {
        let resourceLocator = ResourceLocator()
        let manifestLoader = GraphManifestLoader(resourceLocator: resourceLocator)
        let manifestTargetGenerator = ManifestTargetGenerator(manifestLoader: manifestLoader,
                                                              resourceLocator: resourceLocator)
        let manifestLinter = ManifestLinter()
        let modelLoader = GeneratorModelLoader(manifestLoader: manifestLoader,
                                               manifestLinter: manifestLinter,
                                               manifestTargetGenerator: manifestTargetGenerator)
        let generator = Generator(modelLoader: modelLoader)
        self.init(parser: parser,
                  generator: generator,
                  manifestLoader: manifestLoader,
                  clock: WallClock())
    }

    init(parser: ArgumentParser,
         generator: Generating,
         manifestLoader: GraphManifestLoading,
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
        
        carthageProjectsArgument = subParser.add(option: "--carthage-projects",
                                                 kind: Bool.self,
                                                 usage: "Generate carthage frameworks which have a project manifest as project dependencies.")
        
        verboseArgument = subParser.add(option: "--verbose",
                                        shortName: "-v",
                                        kind: Bool.self,
                                        usage: "Enable verbose logging.")
    }

    func run(with arguments: ArgumentParser.Result) throws {
        let timer = clock.startTimer()
        let path = self.path(arguments: arguments)
        
        let projectOnly = arguments.get(projectOnlyArgument) ?? false
        let carthageProjects = arguments.get(carthageProjectsArgument) ?? false
        let verbose = arguments.get(verboseArgument) ?? false

        CLIOptions.current = .init(
            projectOnly: projectOnly,
            carthageProjects: carthageProjects,
            verbose: verbose
        )

        _ = try generator.generate(at: path,
                                   manifestLoader: manifestLoader)

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
