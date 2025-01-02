import AppKit
import Collections
import Combine
import Mockable

@Mockable
protocol TaskStatusReporting: ObservableObject {
    @MainActor func add(status: TaskStatus)
}

/// Manages task statuses and publishes changes to them.
final class TaskStatusReporter: TaskStatusReporting {
    private var cancellables: Set<AnyCancellable> = []

    /// A set of the statuses of all currently active tasks.
    @Published private(set) var statuses: OrderedSet<TaskStatus> = [] {
        didSet {
            updateSubscriptions()
        }
    }

    /// Adds a task status.
    ///
    /// When a task reaches a ``TaskState/done`` state, the status is
    /// automatically removed from the list of tasks after a short delay.
    /// - Parameter status: The task status to add.
    @MainActor func add(status: TaskStatus) {
        var cancellable: AnyCancellable?
        cancellable = status.$state
            .sink { taskState in
                _ = cancellable

                switch taskState {
                case .done:
                    cancellable = nil
                case .preparing, .running:
                    break
                }
            }

        statuses = statuses.filter {
            switch $0.state {
            case .done:
                return false
            case .preparing, .running:
                return true
            }
        }
        statuses.append(status)
    }

    /// Removes a task status.
    /// - Parameters:
    ///   - status: The task status to remove.
    ///   - withDelay: Whether to delay removal by a few seconds.
    @MainActor func remove(status: TaskStatus, withDelay: Bool = false) {
        Task {
            if withDelay {
                try await Task.sleep(for: .seconds(2))
            }

            statuses.remove(status)
        }
    }

    private func updateSubscriptions() {
        let newCancellables = statuses.map { taskStatus in
            taskStatus.objectWillChange.sink { [weak self] in
                self?.objectWillChange.send()
            }
        }

        cancellables = Set(newCancellables)
    }
}
