import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import TuistGraph
import TuistLoader
import TuistPlugin

struct TaskService {
    private let configLoader: ConfigLoading
    private let manifestLoader: ManifestLoading
    private let pluginService: PluginServicing
    
    init(
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: ManifestLoader()),
        manifestLoader: ManifestLoading = ManifestLoader(),
        pluginService: PluginServicing = PluginService()
    ) {
        self.configLoader = configLoader
        self.manifestLoader = manifestLoader
        self.pluginService = pluginService
    }
    
    func run(
        _ taskName: String,
        path: String?
    ) throws {
        let path = self.path(path)
        let config = try configLoader.loadConfig(path: path)
        let plugins = try pluginService.loadPlugins(using: config)
        manifestLoader.register(plugins: plugins)
        
        let tasks = try manifestLoader.loadTasks(at: path)
        guard tasks.tasks[taskName] != nil else { /* TODO: Throw proper error here */ fatalError() }
        let runArguments = try manifestLoader.tasksBuildArguments(at: path)
        + [
            "--tuist-task",
            taskName,
        ]
        try System.shared.runAndPrint(
            runArguments,
            verbose: false,
            environment: Environment.shared.manifestLoadingVariables
        )
    }
    
    private func path(_ path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
