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
                switch newestTaskStatus?.state {
                case .preparing:
                    MainProgressView(strokeContent: .tertiary, taskCount: taskCount)
                case let .running(_, progress):
                    switch progress {
                    case .indeterminate:
                        MainProgressView(strokeContent: .tertiary, taskCount: taskCount)
                    case let .determinate(totalUnitCount, pendingUnitCount):
                        MainProgressView(
                            strokeContent: .tertiary,
                            totalUnitCount: totalUnitCount,
                            pendingUnitCount: pendingUnitCount,
                            taskCount: taskCount
                        )
                    }
                case .none, .done:
                    EmptyView()
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
        case let .done(message: message):
            return message ?? "Finished"
        }
    }

    private var taskCount: Int {
        taskStatusReporter.statuses.count
    }
}
