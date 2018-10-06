import Basic
import Foundation
import TuistCore
import Utility

class TestCommand: NSObject, Command {
    // MARK: - Command

    static let command = "test"
    static let overview = "Outputs the project unit tests."

    // MARK: - Attributes

    let printer: Printing

    // MARK: - Init

    required init(parser: ArgumentParser) {
        parser.add(subparser: TestCommand.command, overview: TestCommand.overview)
        printer = Printer()
    }

    init(printer: Printing) {
        self.printer = printer
    }

    // MARK: - Command

    func run(with _: ArgumentParser.Result) {
        printer.print(TestCommand.overview)
//        printer.print(Constants.version)
    }
}
