import Foundation

public struct CommandDescriptor {
    public var command: [String]

    /// Creates a command descriptor
    /// - Parameter command: The command and its arguments to perform
    public init(command: [String]) {
        self.command = command
    }
}
