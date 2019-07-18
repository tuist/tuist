import Basic
import Foundation
import SPMUtility
import TuistCore
import TuistGenerator

/// The focus command generates the Xcode workspace and launches it on Xcode.
class FocusCommand: NSObject, Command {
    // MARK: - Static

    /// Command name that is used for the CLI.
    static let command = "focus"

    /// Command description that is shown when using help from the CLI.
    static let overview = "Opens Xcode ready to focus on the project in the current directory."

    // MARK: - Attributes

    /// Generator instance to generate the project workspace.
    private let generator: Generating

    /// File handler instance to interact with the file system.
    private let fileHandler: FileHandling

    /// Manifest loader instance that can load project maifests from disk
    private let manifestLoader: GraphManifestLoading

    /// Opener instance to run open in the system.
    private let opener: Opening

    // MARK: - Init

    /// Initializes the focus command with the argument parser where the command needs to register itself.
    ///
    /// - Parameter parser: Argument parser that parses the CLI arguments.
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
                  generator: generator,
                  fileHandler: fileHandler,
                  manifestLoader: manifestLoader,
                  opener: Opener())
    }

    /// Initializes the focus command with its attributes.
    ///
    /// - Parameters:
    ///   - parser: Argument parser that parses the CLI arguments.
    ///   - generator: Generator instance to generate the project workspace.
    ///   - fileHandler: File handler instance to interact with the file system.
    ///   - manifestLoader: Manifest loader instance that can load project maifests from disk
    ///   - opener: Opener instance to run open in the system.
    init(parser: ArgumentParser,
         generator: Generating,
         fileHandler: FileHandling,
         manifestLoader: GraphManifestLoading,
         opener: Opening) {
        parser.add(subparser: FocusCommand.command, overview: FocusCommand.overview)
        self.generator = generator
        self.fileHandler = fileHandler
        self.manifestLoader = manifestLoader
        self.opener = opener
    }

    func run(with _: ArgumentParser.Result) throws {
        let path = fileHandler.currentPath

        let workspacePath = try generator.generate(at: path, manifestLoader: manifestLoader)

        try opener.open(path: workspacePath)
    }
}
