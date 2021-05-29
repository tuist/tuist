import Foundation
import TSCBasic

/// Side Effect Descriptor
///
/// Describes a side effect that needs to take place without performing it
/// immediately within a component. This allows components to be side effect free,
/// determenistic and much easier to test.
///
/// When part of a `ProjectDescriptor` or `WorkspaceDescriptor`, it
/// can be used in conjunction with `XcodeProjWriter` to perform side effects.
///
/// - seealso: `ProjectDescriptor`
/// - seealso: `WorkspaceDescriptor`
/// - seealso: `XcodeProjWriter`
public enum SideEffectDescriptor: Equatable {
    /// Create / Remove a file
    case file(FileDescriptor)

    /// Create / remove a directory
    case directory(DirectoryDescriptor)

    /// Perform a command
    case command(CommandDescriptor)
}

extension SideEffectDescriptor: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .file(fileDescriptor):
            return fileDescriptor.description
        case let .directory(directoryDescriptor):
            return directoryDescriptor.description
        case let .command(commandDescriptor):
            return commandDescriptor.description
        }
    }
}
