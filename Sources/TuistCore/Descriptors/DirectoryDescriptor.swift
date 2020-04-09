import Basic
import Foundation

/// Directory Descriptor
///
/// Describes a folder operation that needs to take place as
/// part of generating a project or workspace.
///
/// - seealso: `SideEffectsDescriptor`
public struct DirectoryDescriptor: Equatable, Hashable {
    public enum State {
        case present
        case absent
    }

    /// Path to the directory
    public var path: AbsolutePath

    /// The desired state of the directory (`.present` creates a fiile, `.absent` deletes a file)
    public var state: State

    /// Creates a DirectoryDescriptor Descriptor
    /// - Parameters:
    ///   - path: Path to the file
    ///   - state: The desired state of the file (`.present` creates a fiile, `.absent` deletes a file)
    public init(path: AbsolutePath,
                state: DirectoryDescriptor.State = .present) {
        self.path = path
        self.state = state
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
        hasher.combine(state)
    }
}
