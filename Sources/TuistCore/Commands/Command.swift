import Utility

/// Protocol that defines the interface a CLI command.
public protocol Command {
    /// Name of the command that the user should use to execute the command.
    static var command: String { get }

    /// A short sentece that describes what the command is for.
    static var overview: String { get }

    /// Initializes the command with the argument parser. ArgumentParser is defined un the SPM Utility package.
    /// The command needs to register itself in the parser. Otherwise, the command won't be avaible.
    ///
    /// - Parameter parser: Parser where the command should be registered.
    init(parser: ArgumentParser)

    /// Runs the command using the result of parsing the arguments that the user passed to the CLI.
    ///
    /// - Parameter arguments: Result of parsing the arguments that the user passed to the CLI.
    /// - Throws: Errors that are thrown by the underlying command action.
    func run(with arguments: ArgumentParser.Result) throws
}

/// Protocol that defines the interface of a command that can be executed but that is not exposed from the CLI.
public protocol HiddenCommand {
    /// Name of the command that the user should use to execute the command.
    static var command: String { get }

    /// Runs the command using the arguments that the user passed to the CLI.
    ///
    /// - Parameter arguments: Arguments that the user passed to the CLI: cli command arg1 arg2 arg3
    /// - Throws: Errors that are thrown by the underlying command action.
    func run(arguments: [String]) throws

    /// Default constructor
    init()
}

/// It represents a command that accepts the raw argument without parsing them beforehand.
public protocol RawCommand {
    /// Name of the command that the user should use to execute the command.
    static var command: String { get }

    /// A short sentece that describes what the command is for.
    static var overview: String { get }

    /// Initializes the command
    init()

    /// Runs the command using the arguments that the user passed to the CLI.
    ///
    /// - Parameter arguments: Arguments that the user passed to the CLI: cli command arg1 arg2 arg3
    /// - Throws: Errors that are thrown by the underlying command action.
    func run(arguments: [String]) throws
}
