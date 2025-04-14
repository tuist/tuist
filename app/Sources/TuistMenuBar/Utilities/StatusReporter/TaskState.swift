import Foundation

/// The state of a running task.
enum TaskState: Equatable {
    /// The task is preparing to run.
    case preparing
    /// The task is currently running.
    case running(message: String, progress: TaskProgress = .indeterminate)
    /// The task is fully complete and will not perform any further operations.
    case done(message: String?)
}
