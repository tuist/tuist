import Foundation

public struct Tasks {
    public let tasks: [String: Task]
    
    public init(
        _ tasks: [Task]
    ) {
        self.tasks = tasks.reduce(into: [:]) { acc, task in
            acc[task.name] = task
        }
    }
    
    private func runIfNeeded() {
        guard
            let taskCommandLineIndex = CommandLine.arguments.firstIndex(of: "--tuist-task"),
            CommandLine.argc > taskCommandLineIndex,
        else { return }
        let name = CommandLine.arguments[taskCommandLineIndex + 1]
        guard
            let task = tasks[name]
        else {
            // TODO: This should probably be handled when loading Tasks.swift -> we should add dumpIfNeeded call here
            print("No task with name: \(name)")
            exit(1)
        }
        try! task.task()
    }
}
