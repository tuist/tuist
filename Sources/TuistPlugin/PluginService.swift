import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistLoader
import TuistScaffold
import TuistSupport

/// Paths to remote plugin's code and artifacts.
public struct RemotePluginPaths: Equatable, Hashable {
    /// Path to the cloned repository.
    public let repositoryPath: AbsolutePath
    /// Path to the downloaded release artifacts.
    public let releasePath: AbsolutePath?

    public init(
        repositoryPath: AbsolutePath,
        releasePath: AbsolutePath?
    ) {
        self.repositoryPath = repositoryPath
        self.releasePath = releasePath
    }
}

enum PluginServiceError: FatalError, Equatable {
    case missingRemotePlugins([String])
    case invalidURL(String)

    var description: String {
        switch self {
        case let .missingRemotePlugins(plugins):
            return "Remote plugins \(plugins.joined(separator: ", ")) have not been fetched. Try running tuist fetch."
        case let .invalidURL(url):
            return "Invalid URL for the plugin's Github repository: \(url)."
        }
    }

    var type: ErrorType {
        switch self {
        case .missingRemotePlugins:
            return .abort
        case .invalidURL:
            return .bug
        }
    }
}

/// A protocol defining a service for interacting with plugins.
public protocol PluginServicing {
    /// Loads the `Plugins` and returns them as defined in given config.
    /// - Throws: An error if there are issues loading a plugin.
    /// - Returns: The loaded `Plugins` representation.
    func loadPlugins(using config: Config) async throws -> Plugins
    /// - Returns: Array of `RemotePluginPaths` for each remote plugin.
    func remotePluginPaths(using config: Config) throws -> [RemotePluginPaths]
}

enum PluginServiceConstants {
    static let release = "Release"
    static let repository = "Repository"
}

/// A default implementation of `PluginServicing` which loads `Plugins` using the `Config` manifest.
public final class PluginService: PluginServicing { // swiftlint:disable:this type_body_length
    private let manifestLoader: ManifestLoading
    private let templatesDirectoryLocator: TemplatesDirectoryLocating
    private let fileHandler: FileHandling
    private let gitHandler: GitHandling
    private let cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring
    private let fileArchivingFactory: FileArchivingFactorying
    private let fileClient: FileClienting

    /// Creates a `PluginService`.
    /// - Parameters:
    ///   - manifestLoader: A manifest loader for loading plugin manifests.
    ///   - templatesDirectoryLocator: Locator for finding templates for plugins.
    ///   - fileHandler: A file handler for creating plugin directories/related files.
    ///   - gitHandler: A git handler for cloning and interacting with remote plugins.
    ///   - cacheDirectoryProviderFactory: A cache directory provider
    ///   - fileArchivingFactory: FileArchiver for unzipping plugin releases.
    ///   - fileClient: FileClient for downloading plugin releases.
    public init(
        manifestLoader: ManifestLoading = ManifestLoader(),
        templatesDirectoryLocator: TemplatesDirectoryLocating = TemplatesDirectoryLocator(),
        fileHandler: FileHandling = FileHandler.shared,
        gitHandler: GitHandling = GitHandler(),
        cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring = CacheDirectoriesProviderFactory(),
        fileArchivingFactory: FileArchivingFactorying = FileArchivingFactory(),
        fileClient: FileClienting = FileClient()
    ) {
        self.manifestLoader = manifestLoader
        self.templatesDirectoryLocator = templatesDirectoryLocator
        self.fileHandler = fileHandler
        self.gitHandler = gitHandler
        self.cacheDirectoryProviderFactory = cacheDirectoryProviderFactory
        self.fileArchivingFactory = fileArchivingFactory
        self.fileClient = fileClient
    }

    public func remotePluginPaths(using config: Config) throws -> [RemotePluginPaths] {
        try config.plugins.compactMap { pluginLocation in
            switch pluginLocation {
            case .local:
                return nil
            case let .git(url: url, gitReference: .sha(sha), directory, _):
                let pluginCacheDirectory = try self.pluginCacheDirectory(
                    url: url,
                    gitId: sha,
                    config: config
                )
                var repositoryPath = pluginCacheDirectory.appending(component: PluginServiceConstants.repository)
                if let directory = directory {
                    repositoryPath = repositoryPath.appending(RelativePath(directory))
                }
                return RemotePluginPaths(
                    repositoryPath: repositoryPath,
                    releasePath: nil
                )
            case let .git(url: url, gitReference: .tag(tag), directory, _):
                let pluginCacheDirectory = try self.pluginCacheDirectory(
                    url: url,
                    gitId: tag,
                    config: config
                )
                var repositoryPath = pluginCacheDirectory.appending(component: PluginServiceConstants.repository)
                if let directory = directory {
                    repositoryPath = repositoryPath.appending(RelativePath(directory))
                }
                let releasePath = pluginCacheDirectory.appending(component: PluginServiceConstants.release)
                return RemotePluginPaths(
                    repositoryPath: repositoryPath,
                    releasePath: FileHandler.shared.exists(releasePath) ? releasePath : nil
                )
            }
        }
    }

    public func loadPlugins(using config: Config) async throws -> Plugins {
        guard !config.plugins.isEmpty else { return .none }

        try await fetchRemotePlugins(using: config)

        let localPluginPaths: [AbsolutePath] = try config.plugins
            .compactMap { pluginLocation in
                switch pluginLocation {
                case let .local(path):
                    logger.debug("Using plugin \(pluginLocation.description)", metadata: .subsection)
                    return try AbsolutePath(validating: path)
                case .git:
                    return nil
                }
            }
        let localPluginManifests = try localPluginPaths.map(manifestLoader.loadPlugin)

        let remotePluginPaths = try remotePluginPaths(using: config)
        let remotePluginRepositoryPaths = remotePluginPaths.map(\.repositoryPath)
        let remotePluginManifests = try remotePluginRepositoryPaths
            .map(manifestLoader.loadPlugin)
        let pluginPaths = localPluginPaths + remotePluginRepositoryPaths
        let missingRemotePlugins = zip(remotePluginManifests, remotePluginRepositoryPaths)
            .filter { !FileHandler.shared.exists($0.1) }
        if !missingRemotePlugins.isEmpty {
            throw PluginServiceError.missingRemotePlugins(missingRemotePlugins.map(\.0.name))
        }

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

        return Plugins(
            projectDescriptionHelpers: localProjectDescriptionHelperPlugins + remoteProjectDescriptionHelperPlugins,
            templatePaths: templatePaths,
            resourceSynthesizers: resourceSynthesizerPlugins
        )
    }

    func fetchRemotePlugins(using config: Config) async throws {
        for pluginLocation in config.plugins {
            switch pluginLocation {
            case let .git(url, gitReference, _, releaseUrl):
                try await fetchRemotePlugin(
                    url: url,
                    releaseUrl: releaseUrl,
                    gitReference: gitReference,
                    config: config
                )
            case .local:
                continue
            }
        }
    }

    private func fetchRemotePlugin(
        url: String,
        releaseUrl: String?,
        gitReference: PluginLocation.GitReference,
        config: Config
    ) async throws {
        let pluginCacheDirectory = try pluginCacheDirectory(
            url: url,
            gitId: gitReference.raw,
            config: config
        )
        try fetchGitPluginRepository(
            pluginCacheDirectory: pluginCacheDirectory,
            url: url,
            gitId: gitReference.raw
        )
        switch gitReference {
        case .sha:
            break
        case let .tag(tag):
            try await fetchGitPluginRelease(
                pluginCacheDirectory: pluginCacheDirectory,
                url: url,
                gitTag: tag,
                releaseUrl: releaseUrl
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
        let pluginRepositoryDirectory = pluginCacheDirectory.appending(component: PluginServiceConstants.repository)

        guard !fileHandler.exists(pluginRepositoryDirectory) else {
            logger.debug("Using cached git plugin \(url)")
            return
        }

        logger.notice("Cloning plugin from \(url) @ \(gitId)", metadata: .subsection)
        logger.notice("\(pluginRepositoryDirectory.pathString)", metadata: .subsection)
        try gitHandler.clone(url: url, to: pluginRepositoryDirectory)
        try gitHandler.checkout(id: gitId, in: pluginRepositoryDirectory)
    }

    private func fetchGitPluginRelease(
        pluginCacheDirectory: AbsolutePath,
        url: String,
        gitTag: String,
        releaseUrl: String?
    ) async throws {
        let pluginRepositoryDirectory = pluginCacheDirectory.appending(component: PluginServiceConstants.repository)
        // If `Package.swift` exists for the plugin, a Github release should for the given `gitTag` should also exist
        guard FileHandler.shared
            .exists(pluginRepositoryDirectory.appending(component: Constants.DependenciesDirectory.packageSwiftName))
        else { return }

        let pluginReleaseDirectory = pluginCacheDirectory.appending(component: PluginServiceConstants.release)
        guard !fileHandler.exists(pluginReleaseDirectory) else {
            logger.debug("Using cached git plugin release \(url)")
            return
        }

        let plugin = try manifestLoader.loadPlugin(at: pluginRepositoryDirectory)
        guard let releaseURL = getPluginDownloadUrl(gitUrl: url, gitTag: gitTag, pluginName: plugin.name, releaseUrl: releaseUrl)
        else { throw PluginServiceError.invalidURL(url) }

        logger.debug("Cloning plugin release from \(url) @ \(gitTag)")
        try await FileHandler.shared.inTemporaryDirectory { _ in
            // Download the release.
            // Currently, we assume the release path exists.
            let downloadPath = try await self.fileClient.download(url: releaseURL)
            let downloadZipPath = downloadPath.removingLastComponent().appending(component: "release.zip")
            defer {
                try? FileHandler.shared.delete(downloadPath)
                try? FileHandler.shared.delete(downloadZipPath)
            }
            if FileHandler.shared.exists(downloadZipPath) {
                try FileHandler.shared.delete(downloadZipPath)
            }
            try FileHandler.shared.move(from: downloadPath, to: downloadZipPath)

            // Unzip
            let fileUnarchiver = try self.fileArchivingFactory.makeFileUnarchiver(for: downloadZipPath)
            let unarchivedContents = try FileHandler.shared.contentsOfDirectory(
                try fileUnarchiver.unzip()
            )
            defer {
                try? fileUnarchiver.delete()
            }
            try FileHandler.shared.createFolder(pluginReleaseDirectory)
            try unarchivedContents.forEach {
                try FileHandler.shared.move(
                    from: $0,
                    to: pluginReleaseDirectory.appending(component: $0.basename)
                )
            }

            // Mark files as executables (this information is lost during (un)archiving)
            try FileHandler.shared.contentsOfDirectory(pluginReleaseDirectory)
                .filter { $0.basename.hasPrefix("tuist-") }
                .forEach {
                    try System.shared.chmod(.executable, path: $0, options: [.onlyFiles])
                }
        }
    }

    func getPluginDownloadUrl(gitUrl: String, gitTag: String, pluginName: String, releaseUrl: String?) -> URL? {
        if let url = releaseUrl.flatMap(URL.init(string:)) {
            return url
        }

        guard let url = URL(string: gitUrl) else { return nil }
        if gitUrl.lowercased().contains("gitlab") {
            return url.appendingPathComponent("-/releases/\(gitTag)/downloads/\(pluginName).tuist-plugin.zip")
        } else {
            return url.appendingPathComponent("releases/download/\(gitTag)/\(pluginName).tuist-plugin.zip")
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

extension PluginLocation.GitReference {
    fileprivate var raw: String {
        switch self {
        case let .tag(tag):
            return tag
        case let .sha(sha):
            return sha
        }
    }
}
