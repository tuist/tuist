import Basic
import Foundation
import Utility
import xpmcore

class VersionCommand: NSObject, Command {

    // MARK: - Command

    static let command = "version"
    static let overview = "Outputs the current version of xpm."
    let context: CommandsContexting

    // MARK: - Init

    required init(parser: ArgumentParser) {
        parser.add(subparser: VersionCommand.command, overview: VersionCommand.overview)
        context = CommandsContext()
    }

    init(context: CommandsContexting) {
        self.context = context
    }

    // MARK: - Command

    func run(with _: ArgumentParser.Result) {
        context.printer.print(Constants.version)
    }
}
