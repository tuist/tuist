import Basic
import Foundation
import TuistCore
import Utility

class FocusCommand: NSObject, Command {
    // MARK: - Static

    static let command = "focus"
    static let overview = "Opens Xcode ready to focus on the project in the current directory."

    // MARK: - Attributes

    fileprivate let graphLoader: GraphLoading
    fileprivate let workspaceGenerator: WorkspaceGenerating
    fileprivate let printer: Printing
    fileprivate let system: Systeming
    fileprivate let resourceLocator: ResourceLocating
    fileprivate let fileHandler: FileHandling
    fileprivate let opener: Opening

    let configArgument: OptionArgument<String>

    // MARK: - Init

    required convenience init(parser: ArgumentParser) {
        self.init(graphLoader: GraphLoader(),
                  workspaceGenerator: WorkspaceGenerator(),
                  parser: parser)
    }

    init(graphLoader: GraphLoading,
         workspaceGenerator: WorkspaceGenerating,
         parser: ArgumentParser,
         printer: Printing = Printer(),
         system: Systeming = System(),
         resourceLocator: ResourceLocating = ResourceLocator(),
         fileHandler: FileHandling = FileHandler(),
         opener: Opening = Opener()) {
        let subParser = parser.add(subparser: FocusCommand.command, overview: FocusCommand.overview)
        self.graphLoader = graphLoader
        self.workspaceGenerator = workspaceGenerator
        self.printer = printer
        self.system = system
        self.resourceLocator = resourceLocator
        self.fileHandler = fileHandler
        self.opener = opener
        configArgument = subParser.add(option: "--config",
                                       shortName: "-c",
                                       kind: String.self,
                                       usage: "The configuration that will be generated.",
                                       completion: .filename)
    }

    func run(with arguments: ArgumentParser.Result) throws {
        let path = fileHandler.currentPath
        let config = try parseConfig(arguments: arguments)
        let graph = try graphLoader.load(path: path)

        let workspacePath = try workspaceGenerator.generate(path: path,
                                                            graph: graph,
                                                            options: GenerationOptions(buildConfiguration: config),
                                                            directory: .manifest)

        try opener.open(path: workspacePath)
    }

    // MARK: - Fileprivate

    private func parseConfig(arguments: ArgumentParser.Result) throws -> BuildConfiguration {
        var config: BuildConfiguration = .debug
        if let configString = arguments.get(configArgument) {
            guard let buildConfiguration = BuildConfiguration(rawValue: configString.lowercased()) else {
                let error = ArgumentParserError.invalidValue(argument: "config",
                                                             error: ArgumentConversionError.custom("config can only be debug or release"))
                throw error
            }
            config = buildConfiguration
        }
        return config
    }
}
