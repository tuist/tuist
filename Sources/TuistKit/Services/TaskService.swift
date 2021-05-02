import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistLoader
import TuistPlugin
import TuistSupport

enum TaskError: FatalError, Equatable {
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

struct TaskService {
    private let configLoader: ConfigLoading
    private let manifestLoader: ManifestLoading
    private let pluginService: PluginServicing
    private let rootDirectoryLocator: RootDirectoryLocating

    init(
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: ManifestLoader()),
        manifestLoader: ManifestLoading = ManifestLoader(),
        pluginService: PluginServicing = PluginService(),
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()
    ) {
        self.configLoader = configLoader
        self.manifestLoader = manifestLoader
        self.pluginService = pluginService
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    func run(
        _ taskName: String,
        options: [String: String],
        path: String?
    ) throws {
        let task = try loadTask(taskName: taskName, path: path)
        let path = self.path(path)
        let runArguments = try manifestLoader.tasksLoadArguments(at: path)
            + [
                "--tuist-task",
                task.name,
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
    ) throws -> (
        required: [String],
        optional: [String]
    ) {
        let path = self.path(path)
        guard let rootDirectory = rootDirectoryLocator.locate(from: path) else { fatalError() }
        let tasksDirectory = rootDirectory.appending(
            components: Constants.tuistDirectoryName, Constants.tasksDirectoryName
        )
        FileHandler.shared.contentsOfDirectory(tasksDirectory)

//        return task.options.reduce(into: (required: [], optional: [])) { currentValue, attribute in
//            switch attribute {
//            case let .optional(name):
//                currentValue.optional.append(name)
//            case let .required(name):
//                currentValue.required.append(name)
//            }
//        }
    }

    // MARK: - Helpers

    private func loadTask(
        taskName: String,
        path: String?
    ) throws -> Task {
        let path = self.path(path)
        let config = try configLoader.loadConfig(path: path)
        let plugins = try pluginService.loadPlugins(using: config)
        manifestLoader.register(plugins: plugins)

//        let tasks = try FileHandler.shared.contentsOfDirectory(
        guard let task = tasks.tasks[taskName] else { throw TaskError.taskNotFound(taskName, tasks.tasks.map(\.key)) }
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
