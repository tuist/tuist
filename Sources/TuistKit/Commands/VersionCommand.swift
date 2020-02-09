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
        let subParser = parser.add(subparser: VersionCommand.command, overview: VersionCommand.overview)
        _ = subParser.add(option: "--verbose", shortName: "-v", kind: Bool.self)
    }

    // MARK: - Command

    func run(with _: ArgumentParser.Result) {
        logger.info("\(Constants.version)")
    }
}
