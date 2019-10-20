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
    let verboseArgument: OptionArgument<Bool>
    
    let carthageProjectsArgument: OptionArgument<Bool>
    let carthageSubmodulesArgument: OptionArgument<Bool>
    let carthageSSHArgument: OptionArgument<Bool>
    let carthageProjectDirectoryArgument: OptionArgument<String>
    let carthageBuildArgument: OptionArgument<Bool>

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

        pathArgument = subParser.add(
            option: "--path",
            shortName: "-p",
            kind: String.self,
            usage: "The path where the project will be generated.",
            completion: .filename
        )
        
        projectOnlyArgument = subParser.add(
            option: "--project-only",
            kind: Bool.self,
            usage: "Only generate the local project (without generating its dependencies)."
        )
        
        carthageProjectsArgument = subParser.add(
            option: "--carthage-projects",
            kind: Bool.self,
            usage: "Generate carthage frameworks which have a project manifest as project dependencies."
        )
        
        carthageSubmodulesArgument = subParser.add(
            option: "--carthage-submodules",
            kind: Bool.self,
            usage: "true if carthage should use submodules. default false"
        )
        
        carthageSSHArgument = subParser.add(
            option: "--carthage-ssh",
            kind: Bool.self,
            usage: "If carthage should fetch with SSH. default true"
        )
        
        carthageProjectDirectoryArgument = subParser.add(
            option: "--carthage-project-directory",
            kind: String.self,
            usage: "The directory where the Cartfile lives. default cwd",
            completion: .filename
        )
        
        carthageBuildArgument = subParser.add(
            option: "--carthage-build",
            kind: Bool.self,
            usage: "Build carthage dependencies if required, will only build them if carthage projects are not included in the workspace. default false"
        )
        
        verboseArgument = subParser.add(
            option: "--verbose",
            shortName: "-v",
            kind: Bool.self,
            usage: "Enable verbose logging."
        )
        
    }
    
    func hooks(for generator: Generating) -> [GenerateHook] {
        return [
            CarthageHook(generator: generator)
        ]
    }

    func run(with arguments: ArgumentParser.Result) throws {
        let timer = clock.startTimer()
        
        CLI.arguments.path                      = path(arguments: arguments, argument: pathArgument) ?? FileHandler.shared.currentPath
        CLI.arguments.carthage.projects         = arguments.get(carthageProjectsArgument) ?? false
        CLI.arguments.carthage.submodules       = arguments.get(carthageSubmodulesArgument) ?? false
        CLI.arguments.carthage.SSH              = arguments.get(carthageSSHArgument) ?? true
        CLI.arguments.carthage.projectDirectory = path(arguments: arguments, argument: carthageProjectDirectoryArgument)
        CLI.arguments.carthage.build            = arguments.get(carthageBuildArgument) ?? false
        CLI.arguments.verbose                   = arguments.get(verboseArgument) ?? false
        
        let path = CLI.arguments.path
        
        let hooks = self.hooks(for: generator)
        
        for hook in hooks {
            try hook.pre(path: path)
        }
        
        _ = try generator.generate(
            at: path,
            manifestLoader: manifestLoader
        )
        
        for hook in hooks {
            try hook.post(path: path)
        }

        let time = String(format: "%.3f", timer.stop())
        Printer.shared.print(success: "Project generated.")
        Printer.shared.print("Total time taken: \(time)s")
    }

    // MARK: - Fileprivate

    private func path(arguments: ArgumentParser.Result, argument: OptionArgument<String>) -> AbsolutePath? {
        if let path = arguments.get(argument) {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return nil
        }
    }
}
