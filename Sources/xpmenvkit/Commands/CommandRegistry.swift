import Basic
import Foundation
import Utility
import xpmcore

public final class CommandRegistry {

    // MARK: - Attributes

    // Argument parser.
    let parser: ArgumentParser

    /// Commands
    private var commands: [Command] = []

    /// Error handler.
    private let errorHandler: ErrorHandling

    /// Returns the process arguments.
    private let processArguments: () -> [String]

    public convenience init() {
        self.init(processArguments: CommandRegistry.processArguments)
    }

    init(processArguments: @escaping () -> [String],
         errorHandler: ErrorHandling = ErrorHandler()) {
        parser = ArgumentParser(commandName: "xpm",
                                usage: "<command> <options>",
                                overview: "Manage the environment xpm versions.",
                                seeAlso: "")
        self.processArguments = processArguments
        self.errorHandler = errorHandler
    }

    public func run() {
        do {
            if let parsedArguments = try parse() {
            } else {
            }
        } catch let error as FatalError {
            errorHandler.fatal(error: error)
        } catch {
            errorHandler.fatal(error: UnhandledError(error: error))
        }
    }

    private func parse() throws -> ArgumentParser.Result? {
        let arguments = Array(processArguments().dropFirst())
        guard let firstArgument = arguments.first else { return nil }
        if commands.map({ type(of: $0).command }).contains(firstArgument) {
            return try parser.parse(arguments)
        }
        return nil
    }

    fileprivate func register(command: Command.Type) {
        commands.append(command.init(parser: parser))
    }

    // MARK: - Static

    /// Returns the process arguments
    ///
    /// - Returns: process arguments.
    static func processArguments() -> [String] {
        return Array(ProcessInfo.processInfo.arguments)
    }
}
