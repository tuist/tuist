import Basic
import Foundation

/// Side Effect Descriptor
///
/// Describes a side effect that needs to take place without performing it
/// immediately within a component. This allows components to be side effect free,
/// determenistic and much easier to test.
public enum SideEffectDescriptor {
    /// Create / Remove a file
    case file(FileDescriptor)

    /// Perform a command
    case command(CommandDescriptor)
}
