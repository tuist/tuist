import SwiftUI

struct StatusView: View {
    @EnvironmentObject private var taskStatusReporter: TaskStatusReporter

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(mainStatusText)
                .lineLimit(1)
                .truncationMode(.tail)
                .id(mainStatusText)
                .transition(.push(from: .top).animation(.easeInOut))
                .animation(.easeInOut, value: mainStatusText)

            Group {
                if let newestTaskStatus {
                    if case let .running(_, progress) = newestTaskStatus.state,
                       case let .determinate(totalUnitCount, pendingUnitCount) = progress
                    {
                        MainProgressView(
                            strokeContent: .tertiary,
                            totalUnitCount: totalUnitCount,
                            pendingUnitCount: pendingUnitCount,
                            taskCount: taskCount
                        )

                    } else if newestTaskStatus.state != .done || taskCount > 1 {
                        MainProgressView(strokeContent: .tertiary, taskCount: taskCount)
                    }
                }
            }
            .contentShape(Circle())
        }
    }

    private var newestTaskStatus: TaskStatus? {
        taskStatusReporter.statuses.last
    }

    private var mainStatusText: String {
        guard let newestTaskStatus else {
            return "Ready"
        }

        switch newestTaskStatus.state {
        case .preparing:
            return newestTaskStatus.displayName
        case let .running(message: message, progress: _):
            return message
        case .done:
            return "Finished"
        }
    }

    private var taskCount: Int {
        taskStatusReporter.statuses.count
    }
}
