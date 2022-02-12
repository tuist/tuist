import Foundation
import TSCBasic

/// File Descriptor
///
/// Describes a file operation that needs to take place as
/// part of generating a project or workspace.
///
/// - seealso: `SideEffectsDescriptor`
public struct FileDescriptor: Equatable {
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
    public init(
        path: AbsolutePath,
        contents: Data? = nil,
        state: FileDescriptor.State = .present
    ) {
        self.path = path
        self.contents = contents
        self.state = state
    }
}

extension FileDescriptor: CustomStringConvertible {
    public var description: String {
        switch state {
        case .absent:
            return "delete file \(path.pathString)"
        case .present:
            return "create file \(path.pathString)"
        }
    }
}
