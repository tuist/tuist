import ArgumentParser
import Foundation
import TSCBasic

struct CloudPrintHashesCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "print-hashes",
                             abstract: "Print the hashes of the frameworks used by the given project.")
    }

    func run() throws {
        try CloudPrintHashesService().print()
    }
}
