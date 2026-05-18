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
public enum SideEffectDescriptor: Equatable, CustomStringConvertible {
    /// Create / Remove a file
    case file(FileDescriptor)

    /// Create / remove a directory
    case directory(DirectoryDescriptor)

    /// Perform a command
    case command(CommandDescriptor)

    /// Generate a `.xctestplan` file from a `TestPlanDescriptor`.
    ///
    /// Content is produced at execution time because the PBX blueprint identifiers embedded in
    /// the plan only become stable after the owning `.xcodeproj` is written.
    case testPlan(TestPlanDescriptor)

    public var description: String {
        switch self {
        case let .file(fileDescriptor):
            return fileDescriptor.description
        case let .directory(directoryDescriptor):
            return directoryDescriptor.description
        case let .command(commandDescriptor):
            return commandDescriptor.description
        case let .testPlan(descriptor):
            return "generate test plan \(descriptor.path.pathString)"
        }
    }
}
