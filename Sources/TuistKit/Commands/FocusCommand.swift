import Basic
import Foundation
import TuistCore
import Utility

/// The focus command generates the Xcode workspace and launches it on Xcode.
class FocusCommand: NSObject, Command {
    // MARK: - Static

    /// Command name that is used for the CLI.
    static let command = "focus"

    /// Command description that is shown when using help from the CLI.
    static let overview = "Opens Xcode ready to focus on the project in the current directory."

    // MARK: - Attributes

    /// Graph loader instance to load the dependency graph.
    fileprivate let graphLoader: GraphLoading

    /// Workspace generator instance to generate the project workspace.
    fileprivate let workspaceGenerator: WorkspaceGenerating

    /// Printer instance to output messages to the user.
    fileprivate let printer: Printing

    /// System instance to run commands on the system.
    fileprivate let system: Systeming

    /// Resource locator instance used to find files in the system.
    fileprivate let resourceLocator: ResourceLocating

    /// File handler instance to interact with the file system.
    fileprivate let fileHandler: FileHandling

    /// Opener instance to run open in the system.
    fileprivate let opener: Opening

    /// Config argument that allos specifying which configuration the Xcode project should be generated with.
    let configArgument: OptionArgument<String>

    // MARK: - Init

    /// Initializes the focus command with the argument parser where the command needs to register itself.
    ///
    /// - Parameter parser: Argument parser that parses the CLI arguments.
    required convenience init(parser: ArgumentParser) {
        let fileHandler = FileHandler()
        let modelLoader = GeneratorModelLoader(fileHandler: fileHandler,
                                                    manifestLoader: GraphManifestLoader())
        self.init(parser: parser,
                  graphLoader: GraphLoader(modelLoader: modelLoader),
                  workspaceGenerator: WorkspaceGenerator(),
                  printer: Printer(),
                  system: System(),
                  resourceLocator: ResourceLocator(),
                  fileHandler: fileHandler,
                  opener: Opener())
    }

    /// Initializes the focus command with its attributes.
    ///
    /// - Parameters:
    ///   - parser: Argument parser that parses the CLI arguments.
    ///   - graphLoader: Graph loader instance to load the dependency graph.
    ///   - workspaceGenerator: Workspace generator instance to generate the project workspace.
    ///   - printer: Printer instance to output messages to the user.
    ///   - system: System instance to run commands on the system.
    ///   - resourceLocator: Resource locator instance used to find files in the system.
    ///   - fileHandler: File handler instance to interact with the file system.
    ///   - opener: Opener instance to run open in the system.
    ///   - graphUp: Graph up instance to print a warning if the environment is not configured at all.
    init(parser: ArgumentParser,
         graphLoader: GraphLoading,
         workspaceGenerator: WorkspaceGenerating,
         printer: Printing,
         system: Systeming,
         resourceLocator: ResourceLocating,
         fileHandler: FileHandling,
         opener: Opening) {
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

    func run(with _: ArgumentParser.Result) throws {
        let path = fileHandler.currentPath
        let graph = try graphLoader.load(path: path)
        let workspacePath = try workspaceGenerator.generate(path: path,
                                                            graph: graph,
                                                            options: GenerationOptions(),
                                                            directory: .manifest)

        try opener.open(path: workspacePath)
    }
}
