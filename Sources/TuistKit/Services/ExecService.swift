import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistLoader
import TuistPlugin
import TuistSupport
import TuistTasks

enum ExecError: FatalError, Equatable {
    case taskNotFound(String, [String])

    var description: String {
        switch self {
        case let .taskNotFound(task, tasks):
            return "Task \(task) not found. Available tasks are: \(tasks.joined(separator: ", "))"
        }
    }

    var type: ErrorType {
        switch self {
        case .taskNotFound:
            return .abort
        }
    }
}

struct ExecService {
    private let manifestLoader: ManifestLoading
    private let tasksLocator: TasksLocating

    init(
        manifestLoader: ManifestLoading = ManifestLoader(),
        tasksLocator: TasksLocating = TasksLocator()
    ) {
        self.manifestLoader = manifestLoader
        self.tasksLocator = tasksLocator
    }

    func run(
        _ taskName: String,
        options: [String: String],
        path: String?
    ) throws {
        let path = self.path(path)
        let taskPath = try task(with: taskName, path: path)
        let runArguments = try manifestLoader.taskLoadArguments(at: taskPath)
            + [
                "--tuist-task",
                String(data: try JSONEncoder().encode(options), encoding: .utf8)!,
            ]
        try ProcessEnv.chdir(path)
        try System.shared.runAndPrint(
            runArguments,
            verbose: false,
            environment: Environment.shared.manifestLoadingVariables
        )
    }

    func loadTaskOptions(
        taskName: String,
        path: String?
    ) throws -> [String] {
        let path = self.path(path)
        let taskPath = try task(with: taskName, path: path)
        let taskContents = try FileHandler.shared.readTextFile(taskPath)
        let optionsRegex = try NSRegularExpression(pattern: "\\.option\\(\"([^\"]*)\"\\),?", options: [])
        var options: [String] = []
        optionsRegex.enumerateMatches(
            in: taskContents,
            options: [],
            range: NSRange(location: 0, length: taskContents.count)
        ) { match, _, _ in
            guard
                let match = match,
                match.numberOfRanges == 2,
                let range = Range(match.range(at: 1), in: taskContents)
            else { return }
            options.append(
                String(taskContents[range])
            )
        }

        return options
    }

    // MARK: - Helpers

    private func task(with name: String, path: AbsolutePath) throws -> AbsolutePath {
        let tasks: [String: AbsolutePath] = try tasksLocator.locateTasks(at: path)
            .reduce(into: [:]) { acc, current in
                acc[current.basenameWithoutExt.camelCaseToKebabCase()] = current
            }

        guard let task = tasks[name] else { throw ExecError.taskNotFound(name, tasks.map(\.key).sorted()) }
        return task
    }

    private func path(_ path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
