import Basic
import Foundation

/// File Descriptor
///
/// Describes a file operation that needs to take place as
/// part of generating a project or workspace.
///
/// - seealso: `SideEffectsDescriptor`
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
