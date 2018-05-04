import Foundation
import Utility
@testable import xcbuddykit

final class MockCommand: Command {
    var command: String = "command"
    var overview: String = "overview"
    var runArgs: [ArgumentParser.Result] = []
    var runStub: (() -> Void)?
    init(parser: ArgumentParser = ArgumentParser(usage: "usage", overview: "overview")) {
        parser.add(subparser: command, overview: overview)
    }

    init(command: String = "command",
         overview: String = "overview") {
        self.command = command
        self.overview = overview
    }

    func run(with arguments: ArgumentParser.Result) {
        runArgs.append(arguments)
        runStub?()
    }
}
