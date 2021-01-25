import TSCBasic
import TuistCore
import TuistGraph
import TuistLoader
import TuistSupport

/// A default implementation of `PluginServicing` which loads `Plugins` using
/// the `Config` description without it needing to be loaded. The  plugins are first fetched/copied into
/// a cache and the loaded `Plugins` model is returned.
public final class PluginService: PluginServicing {
    private let modelLoader: GeneratorModelLoading
    private let fileHandler: FileHandling
    private let gitHandler: GitHandling
    private let manifestFilesLocator: ManifestFilesLocating

    /// Creates a `PluginService`.
    /// - Parameters:
    ///   - modelLoader: A model loader for loading plugins.
    ///   - fileHandler: A file handler for creating plugin directories/related files.
    ///   - gitHandler: A git handler for cloning and interacting with remote plugins.
    ///   - manifestFilesLocator: A locator for manifest files, used to find location of `Config` manifest in order to load plugins.
    public init(
        modelLoader: GeneratorModelLoading = GeneratorModelLoader(manifestLoader: ManifestLoader(), manifestLinter: ManifestLinter()),
        fileHandler: FileHandling = FileHandler.shared,
        gitHandler: GitHandling = GitHandler(),
        manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator()
    ) {
        self.modelLoader = modelLoader
        self.fileHandler = fileHandler
        self.gitHandler = gitHandler
        self.manifestFilesLocator = manifestFilesLocator
    }

    public func loadPlugins(at path: AbsolutePath) throws -> Plugins {
        guard let configPath = manifestFilesLocator.locateConfig(at: path) else {
            throw PluginServiceError.configNotFound(path)
        }

        let config = try modelLoader.loadConfig(at: configPath)
        return try loadPlugins(using: config)
    }

    public func loadPlugins(using config: Config) throws -> Plugins {
        let pluginPaths = try fetchPlugins(config: config)
        let pluginManifests = try pluginPaths.map(modelLoader.loadPlugin)
        let projectDescriptionHelpers = zip(pluginManifests, pluginPaths)
            .compactMap { plugin, path -> ProjectDescriptionHelpersPlugin? in
                let helpersPath = path.appending(RelativePath(Constants.helpersDirectoryName))
                guard fileHandler.exists(helpersPath) else { return nil }
                return ProjectDescriptionHelpersPlugin(name: plugin.name, path: helpersPath)
            }

        return Plugins(projectDescriptionHelpers: projectDescriptionHelpers)
    }

    private func fetchPlugins(config: Config) throws -> [AbsolutePath] {
        try config.plugins
            .map { plugin in
                switch plugin {
                case let .local(path):
                    logger.debug("Fetching \(plugin.description) at: \(path)")
                    return AbsolutePath(path)
                case let .gitWithBranch(url, id),
                     let .gitWithTag(url, id),
                     let .gitWithSha(url, id):
                    logger.debug("Fetching \(plugin.description) at: \(url) @ \(id)")
                    return try fetchGitPlugin(at: url, with: id)
                }
            }
    }

    /// fetches the git plugins from the remote server and caches them in
    /// the Tuist cache with a unique fingerprint
    private func fetchGitPlugin(at url: String, with gitId: String) throws -> AbsolutePath {
        let fingerprint = "\(url)-\(gitId)".md5
        let pluginDirectory = Environment.shared.cacheDirectory
            .appending(RelativePath(Constants.PluginDirectory.name))
            .appending(RelativePath(fingerprint))

        guard !fileHandler.exists(pluginDirectory) else {
            logger.debug("Using cached git plugin \(url)")
            return pluginDirectory
        }

        try gitHandler.clone(url: url, to: pluginDirectory)
        try gitHandler.checkout(id: gitId, in: pluginDirectory)

        return pluginDirectory
    }
}
