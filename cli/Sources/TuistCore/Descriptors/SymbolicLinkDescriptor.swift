import Path

/// Symbolic Link Descriptor
///
/// Describes a symbolic link operation that needs to take place as part of generating a project
/// or workspace.
///
/// - seealso: `SideEffectDescriptor`
public struct SymbolicLinkDescriptor: Equatable, CustomStringConvertible {
    public enum State {
        case present
        case absent
    }

    /// Path to the symbolic link.
    public var path: AbsolutePath

    /// Path the symbolic link points to.
    public var destination: AbsolutePath

    /// The desired state of the symbolic link.
    public var state: State

    /// Creates a SymbolicLinkDescriptor.
    /// - Parameters:
    ///   - path: Path to the symbolic link.
    ///   - destination: Path the symbolic link points to.
    ///   - state: The desired state of the symbolic link.
    public init(
        path: AbsolutePath,
        destination: AbsolutePath,
        state: SymbolicLinkDescriptor.State = .present
    ) {
        self.path = path
        self.destination = destination
        self.state = state
    }

    public var description: String {
        switch state {
        case .absent:
            return "delete symbolic link \(path.pathString)"
        case .present:
            return "create symbolic link \(path.pathString) -> \(destination.pathString)"
        }
    }
}
