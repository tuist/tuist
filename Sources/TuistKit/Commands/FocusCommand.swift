import Basic
import Foundation
import SPMUtility
import TuistGenerator
import TuistLoader
import TuistSupport

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

    /// Manifest loader instance that can load project maifests from disk
    private let manifestLoader: ManifestLoading

    /// Opener instance to run open in the system.
    private let opener: Opening

    // MARK: - Init

    /// Initializes the focus command with the argument parser where the command needs to register itself.
    ///
    /// - Parameter parser: Argument parser that parses the CLI arguments.
    required convenience init(parser: ArgumentParser) {
        let manifestLoader = ManifestLoader()
        let manifestLinter = ManifestLinter()
        let modelLoader = GeneratorModelLoader(manifestLoader: manifestLoader,
                                               manifestLinter: manifestLinter)
        let generator = Generator(modelLoader: modelLoader)
        self.init(parser: parser,
                  generator: generator,
                  manifestLoader: manifestLoader,
                  opener: Opener())
    }

    /// Initializes the focus command with its attributes.
    ///
    /// - Parameters:
    ///   - parser: Argument parser that parses the CLI arguments.
    ///   - generator: Generator instance to generate the project workspace.
    ///   - manifestLoader: Manifest loader instance that can load project maifests from disk
    ///   - opener: Opener instance to run open in the system.
    init(parser: ArgumentParser,
         generator: Generating,
         manifestLoader: ManifestLoading,
         opener: Opening) {
        parser.add(subparser: FocusCommand.command, overview: FocusCommand.overview)
        self.generator = generator
        self.manifestLoader = manifestLoader
        self.opener = opener
    }

    func run(with _: ArgumentParser.Result) throws {
        let path = FileHandler.shared.currentPath

        let (workspacePath, _) = try generator.generate(at: path,
                                                        manifestLoader: manifestLoader,
                                                        projectOnly: false)

        try opener.open(path: workspacePath)
    }
}
