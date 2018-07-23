import Foundation
import Utility
import TuistCore

final class UpdateCommand: Command {
    /// Command name.
    static var command: String = "update"

    /// Command overview.
    static var overview: String = "Installs the latest version if it's not already installed."

    // MARK: - Attributes

    /// Versions controller.
    private let versionsController: VersionsControlling

    /// Initializes the update command with the argument parser.
    ///
    /// - Parameter parser: argument parser.
    convenience init(parser: ArgumentParser) {
        self.init(parser: parser,
                  versionsController: VersionsController())
    }

    /// Default update command constructor.
    ///
    /// - Parameters:
    ///   - parser: argument parser.
    ///   - versionsController: local versions controller.
    init(parser: ArgumentParser,
         versionsController: VersionsControlling) {
        parser.add(subparser: UpdateCommand.command, overview: UpdateCommand.overview)
        self.versionsController = versionsController
    }

    func run(with _: ArgumentParser.Result) throws {
    }
}
