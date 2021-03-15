import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistLoader
import TuistSupport

/// A protocol defining a service for interacting with plugins.
public protocol PluginServicing {
    /// Loads the `Plugins` and returns them as defined in given config.
    /// - Throws: An error if there are issues fetching or loading a plugin.
    /// - Returns: The loaded `Plugins` representation.
    func loadPlugins(using config: Config) throws -> Plugins
}

/// A default implementation of `PluginServicing` which loads `Plugins` using the `Config` manifest.
public final class PluginService: PluginServicing {
    private let manifestLoader: ManifestLoading
    private let fileHandler: FileHandling
    private let gitHandler: GitHandling

    /// Creates a `PluginService`.
    /// - Parameters:
    ///   - manifestLoader: A manifest loader for loading plugins.
    ///   - configLoader: A configuration loader
    ///   - fileHandler: A file handler for creating plugin directories/related files.
    ///   - gitHandler: A git handler for cloning and interacting with remote plugins.
    public init(
        manifestLoader: ManifestLoading = ManifestLoader(),
        fileHandler: FileHandling = FileHandler.shared,
        gitHandler: GitHandling = GitHandler()
    ) {
        self.manifestLoader = manifestLoader
        self.fileHandler = fileHandler
        self.gitHandler = gitHandler
    }

    public func loadPlugins(using config: Config) throws -> Plugins {
        guard !config.plugins.isEmpty else { return .none }
        logger.notice("Fetching plugin(s)", metadata: .section)

        let localPluginPaths: [AbsolutePath] = config.plugins
            .compactMap { pluginLocation in
                switch pluginLocation {
                case let .local(path):
                    logger.notice("Using plugin \(pluginLocation.description)", metadata: .subsection)
                    return AbsolutePath(path)
                case .gitWithSha,
                     .gitWithTag:
                    return nil
                }
            }
        let localPluginManifests = try localPluginPaths.map(manifestLoader.loadPlugin)

        let remotePluginPaths: [AbsolutePath] = try config.plugins
            .compactMap { pluginLocation in
                switch pluginLocation {
                case let .gitWithSha(url, id),
                     let .gitWithTag(url, id):
                    logger.notice("Downloading plugin \(pluginLocation.description)", metadata: .subsection)
                    return try fetchGitPlugin(at: url, with: id)
                case .local:
                    return nil
                }
            }
        let remotePluginManifests = try remotePluginPaths.map(manifestLoader.loadPlugin)

        let localProjectDescriptionHelperPlugins = zip(localPluginManifests, localPluginPaths)
            .compactMap { plugin, path -> ProjectDescriptionHelpersPlugin? in
                let helpersPath = path.appending(component: Constants.helpersDirectoryName)
                guard fileHandler.exists(helpersPath) else { return nil }
                return ProjectDescriptionHelpersPlugin(name: plugin.name, path: helpersPath, location: .local)
            }

        let remoteProjectDescriptionHelperPlugins = zip(remotePluginManifests, remotePluginPaths)
            .compactMap { plugin, path -> ProjectDescriptionHelpersPlugin? in
                let helpersPath = path.appending(component: Constants.helpersDirectoryName)
                guard fileHandler.exists(helpersPath) else { return nil }
                return ProjectDescriptionHelpersPlugin(name: plugin.name, path: helpersPath, location: .remote)
            }

        return Plugins(
            projectDescriptionHelpers: localProjectDescriptionHelperPlugins + remoteProjectDescriptionHelperPlugins
        )
    }

    /// fetches the git plugins from the remote server and caches them in
    /// the Tuist cache with a unique fingerprint
    private func fetchGitPlugin(at url: String, with gitId: String) throws -> AbsolutePath {
        let fingerprint = "\(url)-\(gitId)".md5
        let pluginDirectory = Environment.shared.cacheDirectory
            .appending(RelativePath(Constants.pluginsDirectoryName))
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
