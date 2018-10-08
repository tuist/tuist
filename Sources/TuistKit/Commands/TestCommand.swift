import Basic
import Foundation
import TuistCore
import Utility

class TestCommand: NSObject, ForwardCommad {

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

    // MARK: - ForwardCommand

    func forward(arguments: [String]) throws {
        let system = System()
        let output = try? system.capture(arguments).throwIfError().stdout
        printer.print(TestCommand.overview)
        printer.print(output!)
    }

    func run(with arguments: ArgumentParser.Result) throws {

    }

}
