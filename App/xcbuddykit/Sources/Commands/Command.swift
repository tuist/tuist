import Utility

/// Protocol that defines a command line command.
public protocol Command {

    /// Command name.
    var command: String { get }

    /// Command overview.
    var overview: String { get }

    /// Initializes the command with the argument parser.
    ///
    /// - Parameter parser: argument parser.
    init(parser: ArgumentParser)
    
    /// Runs the command with the given arguments.
    ///
    /// - Parameter arguments: arguments.
    /// - Throws: an error if the command execution fails.
    func run(with arguments: ArgumentParser.Result) throws
}
