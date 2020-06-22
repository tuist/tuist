import Foundation

/// Command Descriptor
///
/// Describes a command that needs to be executed as part of
/// generating a project or workspace.
///
/// - seealso: `SideEffectsDescriptor`
public struct CommandDescriptor: Equatable {
    public var command: [String]

    /// Creates a command descriptor
    /// - Parameter command: The command and its arguments to perform
    public init(command: [String]) {
        self.command = command
    }

    public init(command: String...) {
        self.init(command: command)
    }
}

extension CommandDescriptor: CustomStringConvertible {
    public var description: String {
        "execute \(command.joined(separator: " "))"
    }
}
