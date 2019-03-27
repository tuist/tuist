import Foundation
import SPMUtility
import TuistCore

public final class MockCommand: Command {
    public static let command: String = "command"
    public static let overview: String = "overview"
    public var runArgs: [ArgumentParser.Result] = []
    public var runStub: (() -> Void)?
    public var runCallCount: UInt = 0

    public init(parser: ArgumentParser = ArgumentParser(usage: "usage", overview: "overview")) {
        parser.add(subparser: MockCommand.command, overview: MockCommand.overview)
    }

    public init() {}

    public func run(with arguments: ArgumentParser.Result) {
        runCallCount += 1
        runArgs.append(arguments)
        runStub?()
    }
}
