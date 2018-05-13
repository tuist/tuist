import Foundation
import Utility
@testable import xcbuddykit

final class MockCommand: Command {
    static let command: String = "command"
    static let overview: String = "overview"
    var runArgs: [ArgumentParser.Result] = []
    var runStub: (() -> Void)?

    init(parser: ArgumentParser = ArgumentParser(usage: "usage", overview: "overview")) {
        parser.add(subparser: MockCommand.command, overview: MockCommand.overview)
    }

    init() {}

    func run(with arguments: ArgumentParser.Result) {
        runArgs.append(arguments)
        runStub?()
    }
}
