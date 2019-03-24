import Basic
import Foundation
import TuistCore
import TuistGenerator
import Utility

class GenerateCommand: NSObject, Command {
    // MARK: - Static

    static let command = "generate"
    static let overview = "Generates an Xcode workspace to start working on the project."

    // MARK: - Attributes

    private let generator: Generating
    private let printer: Printing
    private let fileHandler: FileHandling
    private let manifestLoader: GraphManifestLoading

    let pathArgument: OptionArgument<String>

    // MARK: - Init

    required convenience init(parser: ArgumentParser) {
        let fileHandler = FileHandler()
        let system = System()
        let printer = Printer()
        let resourceLocator = ResourceLocator(fileHandler: fileHandler)
        let manifestLoader = GraphManifestLoader(fileHandler: fileHandler,
                                                 system: system,
                                                 resourceLocator: resourceLocator,
                                                 deprecator: Deprecator(printer: printer))
        let manifestTargetGenerator = ManifestTargetGenerator(manifestLoader: manifestLoader,
                                                              resourceLocator: resourceLocator)
        let modelLoader = GeneratorModelLoader(fileHandler: fileHandler,
                                               manifestLoader: manifestLoader,
                                               manifestTargetGenerator: manifestTargetGenerator)
        let generator = Generator(system: system,
                                  printer: printer,
                                  fileHandler: fileHandler,
                                  modelLoader: modelLoader)
        self.init(parser: parser,
                  printer: printer,
                  fileHandler: fileHandler,
                  generator: generator,
                  manifestLoader: manifestLoader)
    }

    init(parser: ArgumentParser,
         printer: Printing,
         fileHandler: FileHandling,
         generator: Generating,
         manifestLoader: GraphManifestLoading) {
        let subParser = parser.add(subparser: GenerateCommand.command, overview: GenerateCommand.overview)
        self.generator = generator
        self.printer = printer
        self.fileHandler = fileHandler
        self.manifestLoader = manifestLoader

        pathArgument = subParser.add(option: "--path",
                                     shortName: "-p",
                                     kind: String.self,
                                     usage: "The path where the project will be generated.",
                                     completion: .filename)
    }

    func run(with arguments: ArgumentParser.Result) throws {
        let path = self.path(arguments: arguments)

        _ = try generator.generate(at: path,
                                   config: .default,
                                   manifestLoader: manifestLoader)

        printer.print(success: "Project generated.")
    }

    // MARK: - Fileprivate

    private func path(arguments: ArgumentParser.Result) -> AbsolutePath {
        if let path = arguments.get(pathArgument) {
            return AbsolutePath(path, relativeTo: fileHandler.currentPath)
        } else {
            return fileHandler.currentPath
        }
    }
}
