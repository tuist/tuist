import Foundation
import TuistCore
import Utility

final class UpdateCommand: Command {
    // MARK: - Command

    static var command: String = "update"
    static var overview: String = "Installs the latest version if it's not already installed"

    // MARK: - Attributes

    private let updater: Updating
    private let printer: Printing
    let forceArgument: OptionArgument<Bool>

    // MARK: - Init

    convenience init(parser: ArgumentParser) {
        self.init(parser: parser,
                  updater: Updater(),
                  printer: Printer())
    }

    init(parser: ArgumentParser,
         updater: Updating,
         printer: Printing) {
        let subparser = parser.add(subparser: UpdateCommand.command, overview: UpdateCommand.overview)
        self.printer = printer
        self.updater = updater
        forceArgument = subparser.add(option: "--force",
                                      shortName: "-f",
                                      kind: Bool.self,
                                      usage: "Re-installs the latest version compiling it from the source", completion: nil)
    }

    func run(with result: ArgumentParser.Result) throws {
        let force = result.get(forceArgument) ?? false
        printer.print(section: "Checking for updates...")
        try updater.update(force: force)
    }
}
