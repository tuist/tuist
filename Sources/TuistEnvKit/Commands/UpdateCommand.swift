import Foundation
import TuistCore
import Utility

final class UpdateCommand: Command {

    // MARK: - Command

    static var command: String = "update"
    static var overview: String = "Installs the latest version if it's not already installed"

    // MARK: - Attributes

    private let versionsController: VersionsControlling
    private let updater: Updating
    private let printer: Printing

    // MARK: - Init

    convenience init(parser: ArgumentParser) {
        self.init(parser: parser,
                  versionsController: VersionsController(),
                  updater: Updater(),
                  printer: Printer())
    }

    init(parser: ArgumentParser,
         versionsController: VersionsControlling,
         updater: Updating,
         printer: Printer) {
        parser.add(subparser: UpdateCommand.command, overview: UpdateCommand.overview)
        self.versionsController = versionsController
        self.printer = printer
        self.updater = updater
    }

    func run(with _: ArgumentParser.Result) throws {
        printer.print(section: "Checking for updates...")
        try updater.update()
    }
}
