import Basic
import Foundation

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
public enum SideEffectDescriptor: Equatable, Hashable {
    /// Create / Remove a file
    case file(FileDescriptor)

    /// Perform a command
    case command(CommandDescriptor)
}

public extension Sequence where Element == SideEffectDescriptor {
    var files: [FileDescriptor] {
        compactMap {
            switch $0 {
            case let .file(file):
                return file
            default:
                return nil
            }
        }
    }

    var deletions: [AbsolutePath] {
        compactMap {
            switch $0 {
            case let .file(file):
                switch file.state {
                case .absent:
                    return file.path
                default:
                    return nil
                }
            default:
                return nil
            }
        }
    }
}
