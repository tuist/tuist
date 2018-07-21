import Basic
import Foundation
import Utility
import xpmcore

public final class CommandRegistry {

    // MARK: - Attributes

    let parser: ArgumentParser
    var commands: [Command] = []
    private let context: Contexting
    private let commandCheck: CommandChecking
    private let errorHandler: ErrorHandling
    private let processArguments: () -> [String]

    // MARK: - Init

    public convenience init() {
        self.init(context: Context(),
                  commandCheck: CommandCheck(),
                  errorHandler: ErrorHandler(),
                  processArguments: CommandRegistry.processArguments)
        register(command: InitCommand.self)
        register(command: GenerateCommand.self)
        register(command: DumpCommand.self)
        register(command: VersionCommand.self)
        register(command: CreateIssueCommand.self)
    }

    init(context: Contexting,
         commandCheck: CommandChecking,
         errorHandler: ErrorHandling,
         processArguments: @escaping () -> [String]) {
        self.commandCheck = commandCheck
        self.context = context
        self.errorHandler = errorHandler
        parser = ArgumentParser(commandName: "xpm",
                                usage: "<command> <options>",
                                overview: "Generate, build and test your Xcode projects.",
                                seeAlso: "http://docs.xcodepm.com/")
        self.processArguments = processArguments
    }

    public static func processArguments() -> [String] {
        return Array(ProcessInfo.processInfo.arguments)
    }

    // MARK: - Internal

    func register(command: Command.Type) {
        commands.append(command.init(parser: parser))
    }

    // MARK: - Public

    public func run() {
        do {
            let parsedArguments = try parse()
            try process(arguments: parsedArguments)
        } catch let error as FatalError {
            errorHandler.fatal(error: error)
        } catch {
            errorHandler.fatal(error: UnhandledError(error: error))
        }
    }

    // MARK: - Fileprivate

    fileprivate func parse() throws -> ArgumentParser.Result {
        let arguments = Array(processArguments().dropFirst())
        return try parser.parse(arguments)
    }

    fileprivate func process(arguments: ArgumentParser.Result) throws {
        guard let subparser = arguments.subparser(parser),
            let command = commands.first(where: { type(of: $0).command == subparser }) else {
            parser.printUsage(on: stdoutStream)
            return
        }
        try commandCheck.check(command: type(of: command).command)
        try command.run(with: arguments)
    }
}
