import Basic
import Foundation
import RxBlocking
import RxSwift
import SPMUtility
import TuistCache
import TuistCore
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
    private let generator: ProjectGenerating

    /// Opener instance to run open in the system.
    private let opener: Opening

    // MARK: - Init

    /// Initializes the focus command with the argument parser where the command needs to register itself.
    ///
    /// - Parameter parser: Argument parser that parses the CLI arguments.
    required convenience init(parser: ArgumentParser) {
        let generatorCacheMapper = GeneratorCacheMapper()
        let graphMapper = AnyGraphMapper(mapper: { (try generatorCacheMapper.map(graph: $0).toBlocking().single(), []) })
        self.init(parser: parser,
                  generator: ProjectGenerator(graphMapper: graphMapper),
                  opener: Opener())
    }

    /// Initializes the focus command with its attributes.
    ///
    /// - Parameters:
    ///   - parser: Argument parser that parses the CLI arguments.
    ///   - generator: Generator instance to generate the project workspace.
    ///   - opener: Opener instance to run open in the system.
    init(parser: ArgumentParser,
         generator: ProjectGenerating,
         opener: Opening) {
        parser.add(subparser: FocusCommand.command, overview: FocusCommand.overview)
        self.generator = generator
        self.opener = opener
    }

    func run(with _: ArgumentParser.Result) throws {
        let path = FileHandler.shared.currentPath

        let workspacePath = try generator.generate(path: path,
                                                   projectOnly: false)

        try opener.open(path: workspacePath)
    }
}
