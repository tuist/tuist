import Basic
import Foundation
import Utility

public final class CommandRegistry {
    let parser: ArgumentParser
    var commands: [Command] = []
    private let processArguments: () -> [String]

    public convenience init() {
        self.init(processArguments: CommandRegistry.processArguments)
        register(command: ReleaseCommand.self)
    }

    init(processArguments: @escaping () -> [String]) {
        parser = ArgumentParser(usage: "<command> <options>",
                                overview: "Includes a set of tools to work with the project")
        self.processArguments = processArguments
    }

    public static func processArguments() -> [String] {
        return Array(ProcessInfo.processInfo.arguments)
    }

    func register(command: Command.Type) {
        commands.append(command.init(parser: parser))
    }

    public func run() throws {
        let parsedArguments = try parse()
        try process(arguments: parsedArguments)
    }

    private func parse() throws -> ArgumentParser.Result {
        let arguments = Array(processArguments().dropFirst())
        return try parser.parse(arguments)
    }

    private func process(arguments: ArgumentParser.Result) throws {
        guard let subparser = arguments.subparser(parser),
            let command = commands.first(where: { type(of: $0).command == subparser }) else {
            parser.printUsage(on: stdoutStream)
            return
        }
        try command.run(with: arguments)
    }
}
