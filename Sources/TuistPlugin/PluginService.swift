import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistLoader
import TuistScaffold
import TuistSupport

public struct RemotePluginPaths {
    public let repositoryPath: AbsolutePath
    public let releasePath: AbsolutePath?
    
    public init(
        repositoryPath: AbsolutePath,
        releasePath: AbsolutePath?
    ) {
        self.repositoryPath = repositoryPath
        self.releasePath = releasePath
    }
}

/// A protocol defining a service for interacting with plugins.
public protocol PluginServicing {
    /// Loads the `Plugins` and returns them as defined in given config.
    /// - Throws: An error if there are issues fetching or loading a plugin.
    /// - Returns: The loaded `Plugins` representation.
    func loadPlugins(using config: Config) throws -> Plugins
    func fetchRemotePlugins(using config: Config) throws
    func remotePluginPaths(using config: Config) throws -> [RemotePluginPaths]
}

/// A default implementation of `PluginServicing` which loads `Plugins` using the `Config` manifest.
public final class PluginService: PluginServicing {
    private let manifestLoader: ManifestLoading
    private let templatesDirectoryLocator: TemplatesDirectoryLocating
    private let fileHandler: FileHandling
    private let gitHandler: GitHandling
    private let cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring
    
    /// Creates a `PluginService`.
    /// - Parameters:
    ///   - manifestLoader: A manifest loader for loading plugin manifests.
    ///   - templateDirectoryLocator: Locator for finding templates for plugins.
    ///   - fileHandler: A file handler for creating plugin directories/related files.
    ///   - gitHandler: A git handler for cloning and interacting with remote plugins.
    public init(
        manifestLoader: ManifestLoading = ManifestLoader(),
        templatesDirectoryLocator: TemplatesDirectoryLocating = TemplatesDirectoryLocator(),
        fileHandler: FileHandling = FileHandler.shared,
        gitHandler: GitHandling = GitHandler(),
        cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring = CacheDirectoriesProviderFactory()
    ) {
        self.manifestLoader = manifestLoader
        self.templatesDirectoryLocator = templatesDirectoryLocator
        self.fileHandler = fileHandler
        self.gitHandler = gitHandler
        self.cacheDirectoryProviderFactory = cacheDirectoryProviderFactory
    }
    
    public func fetchRemotePlugins(using config: Config) throws {
        try config.plugins
            .forEach { pluginLocation in
                switch pluginLocation {
                case let .git(url, gitID):
                    try fetchRemotePlugin(
                        url: url,
                        gitID: gitID,
                        config: config
                    )
                case .local:
                    return
                }
            }
    }
    
    public func remotePluginPaths(using config: Config) throws -> [RemotePluginPaths] {
        return try config.plugins.compactMap { pluginLocation in
            switch pluginLocation {
            case .local:
                return nil
            case let .git(url: url, gitID: .sha(sha)):
                let pluginCacheDirectory = try self.pluginCacheDirectory(
                    url: url,
                    gitId: sha,
                    config: config
                )
                return RemotePluginPaths(
                    repositoryPath: pluginCacheDirectory.appending(component: "Repository"),
                    releasePath: nil
                )
            case let .git(url: url, gitID: .tag(tag)):
                let pluginCacheDirectory = try self.pluginCacheDirectory(
                    url: url,
                    gitId: tag,
                    config: config
                )
                let releasePath = pluginCacheDirectory.appending(component: "Release")
                return RemotePluginPaths(
                    repositoryPath: pluginCacheDirectory.appending(component: "Repository"),
                    releasePath: FileHandler.shared.exists(releasePath) ? releasePath : nil
                )
            }
        }
    }
    
    // swiftlint:disable:next function_body_length
    public func loadPlugins(using config: Config) throws -> Plugins {
        guard !config.plugins.isEmpty else { return .none }
        
        let localPluginPaths: [AbsolutePath] = config.plugins
            .compactMap { pluginLocation in
                switch pluginLocation {
                case let .local(path):
                    logger.debug("Using plugin \(pluginLocation.description)", metadata: .subsection)
                    return AbsolutePath(path)
                case .git:
                    return nil
                }
            }
        let localPluginManifests = try localPluginPaths.map(manifestLoader.loadPlugin)
        
        let remotePluginPaths = try self.remotePluginPaths(using: config)
        let remotePluginRepositoryPaths = remotePluginPaths.map(\.repositoryPath)
        let remotePluginManifests = try remotePluginRepositoryPaths
            .map(manifestLoader.loadPlugin)
        let pluginPaths = localPluginPaths + remotePluginRepositoryPaths
        
        let localProjectDescriptionHelperPlugins = zip(localPluginManifests, localPluginPaths)
            .compactMap { plugin, path -> ProjectDescriptionHelpersPlugin? in
                projectDescriptionHelpersPlugin(name: plugin.name, pluginPath: path, location: .local)
            }
        
        let remoteProjectDescriptionHelperPlugins = zip(remotePluginManifests, remotePluginRepositoryPaths)
            .compactMap { plugin, path -> ProjectDescriptionHelpersPlugin? in
                projectDescriptionHelpersPlugin(name: plugin.name, pluginPath: path, location: .remote)
            }
        
        let templatePaths = try pluginPaths.flatMap(templatePaths(pluginPath:))
        let resourceSynthesizerPlugins = zip(
            (localPluginManifests + remotePluginManifests).map(\.name),
            pluginPaths
                .map { $0.appending(component: Constants.resourceSynthesizersDirectoryName) }
        )
            .filter { _, path in FileHandler.shared.exists(path) }
            .map(PluginResourceSynthesizer.init)
        
        let tasks = zip(
            (localPluginManifests + remotePluginManifests).map(\.name),
            pluginPaths
                .map { $0.appending(component: Constants.tasksDirectoryName) }
        )
            .filter { _, path in FileHandler.shared.exists(path) }
            .map(PluginTasks.init)
        
        return Plugins(
            projectDescriptionHelpers: localProjectDescriptionHelperPlugins + remoteProjectDescriptionHelperPlugins,
            templatePaths: templatePaths,
            resourceSynthesizers: resourceSynthesizerPlugins,
            tasks: tasks
        )
    }
    
    private func fetchRemotePlugin(
        url: String,
        gitID: PluginLocation.GitID,
        config: Config
    ) throws {
        let pluginCacheDirectory = try self.pluginCacheDirectory(
            url: url,
            gitId: gitID.raw,
            config: config
        )
        try fetchGitPluginRepository(
            pluginCacheDirectory: pluginCacheDirectory,
            url: url,
            gitId: gitID.raw
        )
        switch gitID {
        case .sha:
            break
        case let .tag(tag):
            try fetchGitPluginRelease(
                pluginCacheDirectory: pluginCacheDirectory,
                url: url,
                gitTag: tag
            )
        }
    }
    
    private func pluginCacheDirectory(
        url: String,
        gitId: String,
        config: Config
    ) throws -> AbsolutePath {
        let cacheDirectories = try cacheDirectoryProviderFactory.cacheDirectories(config: config)
        let cacheDirectory = cacheDirectories.cacheDirectory(for: .plugins)
        let fingerprint = "\(url)-\(gitId)".md5
        return cacheDirectory
            .appending(component: fingerprint)
    }
    
    /// Fetches the git plugins from the remote server and caches them in
    /// the Tuist cache with a unique fingerprint
    private func fetchGitPluginRepository(pluginCacheDirectory: AbsolutePath, url: String, gitId: String) throws {
        let pluginRepositoryDirectory = pluginCacheDirectory.appending(component: "Repository")
        
        guard !fileHandler.exists(pluginRepositoryDirectory) else {
            logger.debug("Using cached git plugin \(url)")
            return
        }
        
        logger.notice("Cloning plugin from \(url) @ \(gitId)", metadata: .subsection)
        try gitHandler.clone(url: url, to: pluginRepositoryDirectory)
        try gitHandler.checkout(id: gitId, in: pluginRepositoryDirectory)
    }
    
    private func fetchGitPluginRelease(pluginCacheDirectory: AbsolutePath, url: String, gitTag: String) throws {
        let pluginRepositoryDirectory = pluginCacheDirectory.appending(component: "Repository")
        // Make sure that `Package.swift` - if so, a release should also has been released
        guard FileHandler.shared.exists(pluginRepositoryDirectory.appending(component: Constants.DependenciesDirectory.packageSwiftName))
        else { return }
        
        let pluginReleaseDirectory = pluginCacheDirectory.appending(component: "Release")
        guard !fileHandler.exists(pluginReleaseDirectory) else {
            logger.debug("Using cached git plugin release \(url)")
            return
        }
        
        let plugin = try manifestLoader.loadPlugin(at: pluginRepositoryDirectory)
        guard
            let releaseURL = URL(string: url)?.appendingPathComponent("releases/download/\(gitTag)/\(plugin.name).tuist-plugin.zip")
        // TODO: Throw error instead
        else { return }
        
        logger.debug("Cloning plugin release from \(url) @ \(gitTag)")
        try FileHandler.shared.inTemporaryDirectory { temporaryDirectory in
            let downloadPath = temporaryDirectory.appending(component: "release.zip")
            try System.shared.run("/usr/bin/curl", "-LSs", "--output", downloadPath.pathString, releaseURL.absoluteString)
            
            // Unzip
            try System.shared.run(
                "/usr/bin/unzip",
                "-q", downloadPath.pathString,
                "-d", pluginReleaseDirectory.pathString
            )
            try FileHandler.shared.contentsOfDirectory(pluginReleaseDirectory)
                .filter { $0.basename.hasPrefix("tuist-") }
                .forEach {
                    try System.shared.run("/bin/chmod", "+x", $0.pathString)
                }
        }
    }
    
    private func projectDescriptionHelpersPlugin(
        name: String,
        pluginPath: AbsolutePath,
        location: ProjectDescriptionHelpersPlugin.Location
    ) -> ProjectDescriptionHelpersPlugin? {
        let helpersPath = pluginPath.appending(component: Constants.helpersDirectoryName)
        guard fileHandler.exists(helpersPath) else { return nil }
        return ProjectDescriptionHelpersPlugin(name: name, path: helpersPath, location: location)
    }
    
    private func templatePaths(
        pluginPath: AbsolutePath
    ) throws -> [AbsolutePath] {
        let templatesPath = pluginPath.appending(component: Constants.templatesDirectoryName)
        guard fileHandler.exists(templatesPath) else { return [] }
        return try templatesDirectoryLocator.templatePluginDirectories(at: templatesPath)
    }
}

private extension PluginLocation.GitID {
    var raw: String {
        switch self {
        case let .tag(tag):
            return tag
        case let .sha(sha):
            return sha
        }
    }
}
