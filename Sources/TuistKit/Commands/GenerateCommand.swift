import Basic
import Foundation
import TuistCore
import Utility

class GenerateCommand: NSObject, Command {
    // MARK: - Static

    static let command = "generate"
    static let overview = "Generates an Xcode workspace to start working on the project."

    // MARK: - Attributes

    fileprivate let graphLoader: GraphLoading
    fileprivate let workspaceGenerator: WorkspaceGenerating
    fileprivate let printer: Printing
    fileprivate let system: Systeming
    fileprivate let resourceLocator: ResourceLocating
    fileprivate let graphUp: GraphUpping

    let pathArgument: OptionArgument<String>

    // MARK: - Init

    required convenience init(parser: ArgumentParser) {
        let system = System()
        let printer = Printer()
        self.init(graphLoader: GraphLoader(),
                  workspaceGenerator: WorkspaceGenerator(),
                  parser: parser,
                  printer: printer,
                  system: system,
                  resourceLocator: ResourceLocator(),
                  graphUp: GraphUp(printer: printer, system: system))
    }

    init(graphLoader: GraphLoading,
         workspaceGenerator: WorkspaceGenerating,
         parser: ArgumentParser,
         printer: Printing,
         system: Systeming,
         resourceLocator: ResourceLocating,
         graphUp: GraphUpping) {
        let subParser = parser.add(subparser: GenerateCommand.command, overview: GenerateCommand.overview)
        self.graphLoader = graphLoader
        self.workspaceGenerator = workspaceGenerator
        self.printer = printer
        self.system = system
        self.resourceLocator = resourceLocator
        self.graphUp = graphUp
        pathArgument = subParser.add(option: "--path",
                                     shortName: "-p",
                                     kind: String.self,
                                     usage: "The path where the project will be generated.",
                                     completion: .filename)
    }

    func run(with arguments: ArgumentParser.Result) throws {
        let path = self.path(arguments: arguments)
        let graph = try graphLoader.load(path: path)

        if try !graphUp.isMet(graph: graph) {
            printer.print(warning: "You can run 'tuist up' to install everything you need to run this project")
        }

        try workspaceGenerator.generate(path: path,
                                        graph: graph,
                                        options: GenerationOptions(),
                                        directory: .manifest)

        printer.print(success: "Project generated.")
    }

    // MARK: - Fileprivate

    fileprivate func path(arguments: ArgumentParser.Result) -> AbsolutePath {
        if let path = arguments.get(pathArgument) {
            return AbsolutePath(path, relativeTo: AbsolutePath.current)
        } else {
            return AbsolutePath.current
        }
    }
}
