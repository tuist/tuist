import Basic
import Foundation
import SPMUtility
import TuistSupport

class VersionCommand: NSObject, Command {
    // MARK: - Command

    static let command = "version"
    static let overview = "Outputs the current version of tuist."

    // MARK: - Init

    required init(parser: ArgumentParser) {
        parser.add(subparser: VersionCommand.command, overview: VersionCommand.overview)
    }

    // MARK: - Command

    func run(with _: ArgumentParser.Result) {
        Printer.shared.print("\(Constants.version)")
    }
}
