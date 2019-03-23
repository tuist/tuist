import Basic
import Foundation
import TuistCore
import Utility

public final class CommandRegistry {
    // MARK: - Attributes

    let parser: ArgumentParser
    var commands: [Command] = []
    private let errorHandler: ErrorHandling
    private let processArguments: () -> [String]
    private let commandRunner: CommandRunning

    // MARK: - Init

    public convenience init() {
        self.init(processArguments: CommandRegistry.processArguments,
                  commands: [
                      LocalCommand.self,
                      BundleCommand.self,
                      UpdateCommand.self,
                      InstallCommand.self,
                      UninstallCommand.self,
                  ])
    }

    init(processArguments: @escaping () -> [String],
         errorHandler: ErrorHandling = ErrorHandler(),
         commandRunner: CommandRunning = CommandRunner(),
         commands: [Command.Type] = []) {
        parser = ArgumentParser(commandName: "tuist",
                                usage: "<command> <options>",
                                overview: "Manage the environment tuist versions.")
        self.processArguments = processArguments
        self.errorHandler = errorHandler
        self.commandRunner = commandRunner
        commands.forEach(register)
    }

    // MARK: - Public

    public func run() {
        do {
            if processArguments().dropFirst().first == "--help-env" {
                parser.printUsage(on: stdoutStream)
            } else if let parsedArguments = try parse() {
                try process(arguments: parsedArguments)
            } else {
                try commandRunner.run()
            }
        } catch let error as FatalError {
            errorHandler.fatal(error: error)
        } catch {
            errorHandler.fatal(error: UnhandledError(error: error))
        }
    }

    // MARK: - Fileprivate

    private func parse() throws -> ArgumentParser.Result? {
        let arguments = Array(processArguments().dropFirst())
        guard let firstArgument = arguments.first else { return nil }
        if commands.map({ type(of: $0).command }).contains(firstArgument) {
            return try parser.parse(arguments)
        }
        return nil
    }

    private func register(command: Command.Type) {
        commands.append(command.init(parser: parser))
    }

    private func process(arguments: ArgumentParser.Result) throws {
        let subparser = arguments.subparser(parser)!
        let command = commands.first(where: { type(of: $0).command == subparser })!
        try command.run(with: arguments)
    }

    // MARK: - Static

    static func processArguments() -> [String] {
        return Array(ProcessInfo.processInfo.arguments)
    }
}
