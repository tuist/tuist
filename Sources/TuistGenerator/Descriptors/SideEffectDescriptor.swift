import Basic
import Foundation
import XcodeProj

/// Side Effect Descriptor
///
/// Describes a side effect that needs to take place without performing it
/// immediately within a component. This allows components to be side effect free,
/// determenistic and much easier to test.
public enum SideEffectDescriptor {
    /// Create / Remove a file
    case file(FileDescriptor)

    /// Perform a command
    case command(GeneratedCommand)
}

public struct FileDescriptor {
    public enum State {
        case present
        case absent
    }

    /// Path to the file
    public var path: AbsolutePath

    /// The contents of the file
    public var contents: Data?

    /// The desired state of the file (`.present` creates a fiile, `.absent` deletes a file)
    public var state: State

    /// Creates a File Descriptor
    /// - Parameters:
    ///   - path: Path to the file
    ///   - contents: The contents of the file (Optional)
    ///   - state: The desired state of the file (`.present` creates a fiile, `.absent` deletes a file)
    public init(path: AbsolutePath,
                contents: Data? = nil,
                state: FileDescriptor.State = .present) {
        self.path = path
        self.contents = contents
        self.state = state
    }
}

public struct GeneratedCommand {
    public var command: [String]

    public init(command: [String]) {
        self.command = command
    }
}
