import Utility

/// Protocol that defines a command line command.
protocol Command {
    /// Command name. This name is used from the command line to call the command.
    var command: String { get }

    /// Command overview. It's used to show more details about your command from the command line.
    var overview: String { get }

    /// Initializes the command with the argument parser.
    ///
    /// - Parameter parser: argument parser.
    init(parser: ArgumentParser)

    /// Runs the command with the given arguments.
    ///
    /// - Parameter arguments: arguments.
    /// - Throws: an error if the command execution fails.
    func run(with arguments: ArgumentParser.Result)
}
