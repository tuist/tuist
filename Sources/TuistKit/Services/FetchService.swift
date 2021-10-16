import Foundation
import TSCBasic
import TuistPlugin
import TuistSupport
import TuistLoader

final class FetchService {
    private let pluginService: PluginServicing
    private let configLoader: ConfigLoading
    
    init(
        pluginService: PluginServicing = PluginService(),
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: CachedManifestLoader())
    ) {
        self.pluginService = pluginService
        self.configLoader = configLoader
    }

    func run(path: String?) throws {
        let path = self.path(path)
        let config = try configLoader.loadConfig(path: path)
        try pluginService.fetchRemotePlugins(using: config)
    }
    
    // MARK: - Helpers

    private func path(_ path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: currentPath)
        } else {
            return currentPath
        }
    }

    private var currentPath: AbsolutePath {
        FileHandler.shared.currentPath
    }
}

