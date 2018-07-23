import Basic
import Foundation
import Utility
import TuistCore

class VersionCommand: NSObject, Command {

    // MARK: - Command

    static let command = "version"
    static let overview = "Outputs the current version of tuist."
    
    // MARK: - Attributes
    
    let printer: Printing

    // MARK: - Init

    required init(parser: ArgumentParser) {
        parser.add(subparser: VersionCommand.command, overview: VersionCommand.overview)
        printer = Printer()
    }

    init(printer: Printing) {
        self.printer = printer
    }

    // MARK: - Command

    func run(with _: ArgumentParser.Result) {
        printer.print(Constants.version)
    }
}
