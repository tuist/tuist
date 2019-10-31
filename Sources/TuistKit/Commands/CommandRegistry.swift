import Basic
import Foundation
import SPMUtility
import TuistSupport

public final class CommandRegistry {
    // MARK: - Attributes

    let parser: ArgumentParser
    var commands: [Command] = []
    var rawCommands: [RawCommand] = []
    var hiddenCommands: [String: HiddenCommand] = [:]
    private let errorHandler: ErrorHandling
    private let processArguments: () -> [String]

    // MARK: - Init

    public convenience init() {
        self.init(errorHandler: ErrorHandler(),
                  processArguments: CommandRegistry.processArguments)
        register(command: InitCommand.self)
        register(command: GenerateCommand.self)
        register(command: DumpCommand.self)
        register(command: VersionCommand.self)
        register(command: CreateIssueCommand.self)
        register(command: FocusCommand.self)
        register(command: UpCommand.self)
        register(command: GraphCommand.self)
        register(rawCommand: BuildCommand.self)
    }

    init(errorHandler: ErrorHandling,
         processArguments: @escaping () -> [String]) {
        self.errorHandler = errorHandler
        parser = ArgumentParser(commandName: "tuist",
                                usage: "<command> <options>",
                                overview: "Generate, build and test your Xcode projects.")
        self.processArguments = processArguments
    }

    public static func processArguments() -> [String] {
        return Array(ProcessInfo.processInfo.arguments)
    }

    // MARK: - Internal

    func register(command: Command.Type) {
        commands.append(command.init(parser: parser))
    }

    func register(hiddenCommand command: HiddenCommand.Type) {
        hiddenCommands[command.command] = command.init()
    }

    func register(rawCommand command: RawCommand.Type) {
        rawCommands.append(command.init())
        parser.add(subparser: command.command, overview: command.overview)
    }

    // MARK: - Public

    public func run() {
        do {
            // Hidden command
            if let hiddenCommand = hiddenCommand() {
                try hiddenCommand.run(arguments: argumentsDroppingCommand())

                // Raw command
            } else if let commandName = commandName(),
                let command = rawCommands.first(where: { type(of: $0).command == commandName }) {
                try command.run(arguments: argumentsDroppingCommand())

                // Normal command
            } else {
                let parsedArguments = try parse()
                try process(arguments: parsedArguments)
            }
        } catch let error as FatalError {
            errorHandler.fatal(error: error)
        } catch {
            errorHandler.fatal(error: UnhandledError(error: error))
        }
    }

    // MARK: - Fileprivate

    func argumentsDroppingCommand() -> [String] {
        return Array(processArguments().dropFirst(2))
    }

    /// Returns the command name.
    ///
    /// - Returns: Command name.
    func commandName() -> String? {
        let arguments = processArguments()
        if arguments.count < 2 { return nil }
        return arguments[1]
    }

    private func parse() throws -> ArgumentParser.Result {
        let arguments = Array(processArguments().dropFirst())
        return try parser.parse(arguments)
    }

    private func hiddenCommand() -> HiddenCommand? {
        let arguments = Array(processArguments().dropFirst())
        guard let commandName = arguments.first else { return nil }
        return hiddenCommands[commandName]
    }

    private func process(arguments: ArgumentParser.Result) throws {
        guard let subparser = arguments.subparser(parser) else {
            parser.printUsage(on: stdoutStream)
            return
        }
        if let command = commands.first(where: { type(of: $0).command == subparser }) {
            try command.run(with: arguments)
        }
    }
}
