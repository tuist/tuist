import FileSystem
import Foundation
import Path
import TuistCore
import TuistGit
import TuistHTTP
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
            return "Remote plugins \(plugins.joined(separator: ", ")) have not been fetched. Try running 'tuist install'."
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
    func loadPlugins(using configGeneratedProjectsOptions: TuistGeneratedProjectOptions) async throws -> Plugins
    func remotePluginPaths(using configGeneratedProjectsOptions: TuistGeneratedProjectOptions) async throws -> [RemotePluginPaths]
}

enum PluginServiceConstants {
    static let release = "Release"
    static let repository = "Repository"
}

/// A default implementation of `PluginServicing` which loads `Plugins` using the `Config` manifest.
public struct PluginService: PluginServicing {
    private let manifestLoader: ManifestLoading
    private let templatesDirectoryLocator: TemplatesDirectoryLocating
    private let fileHandler: FileHandling
    private let gitController: GitControlling
    private let cacheDirectoriesProvider: CacheDirectoriesProviding
    private let fileArchivingFactory: FileArchivingFactorying
    private let fileClient: FileClienting
    private let fileSystem: FileSystem

    /// Creates a `PluginService`.
    /// - Parameters:
    ///   - manifestLoader: A manifest loader for loading plugin manifests.
    ///   - templatesDirectoryLocator: Locator for finding templates for plugins.
    ///   - fileHandler: A file handler for creating plugin directories/related files.
    ///   - gitController: A git handler for cloning and interacting with remote plugins.
    ///   - cacheDirectoriesProvider: A cache directory provider
    ///   - fileArchivingFactory: FileArchiver for unzipping plugin releases.
    ///   - fileClient: FileClient for downloading plugin releases.
    public init(
        manifestLoader: ManifestLoading = ManifestLoader(),
        templatesDirectoryLocator: TemplatesDirectoryLocating = TemplatesDirectoryLocator(),
        fileHandler: FileHandling = FileHandler.shared,
        gitController: GitControlling = GitController(),
        cacheDirectoriesProvider: CacheDirectoriesProviding = CacheDirectoriesProvider(),
        fileArchivingFactory: FileArchivingFactorying = FileArchivingFactory(),
        fileClient: FileClienting = FileClient(),
        fileSystem: FileSystem = FileSystem()
    ) {
        self.manifestLoader = manifestLoader
        self.templatesDirectoryLocator = templatesDirectoryLocator
        self.fileHandler = fileHandler
        self.gitController = gitController
        self.cacheDirectoriesProvider = cacheDirectoriesProvider
        self.fileArchivingFactory = fileArchivingFactory
        self.fileClient = fileClient
        self.fileSystem = fileSystem
    }

    public func remotePluginPaths(using configGeneratedProjectsOptions: TuistGeneratedProjectOptions) async throws
        -> [RemotePluginPaths]
    {
        try await configGeneratedProjectsOptions.plugins.concurrentCompactMap { pluginLocation -> RemotePluginPaths? in
            switch pluginLocation {
            case .local:
                return nil
            case let .git(url: url, gitReference: .sha(sha), directory, _):
                let pluginCacheDirectory = try pluginCacheDirectory(
                    url: url,
                    gitId: sha
                )
                var repositoryPath = pluginCacheDirectory.appending(component: PluginServiceConstants.repository)
                if let directory {
                    repositoryPath = repositoryPath.appending(try RelativePath(validating: directory))
                }
                return RemotePluginPaths(
                    repositoryPath: repositoryPath,
                    releasePath: nil
                )
            case let .git(url: url, gitReference: .tag(tag), directory, _):
                let pluginCacheDirectory = try pluginCacheDirectory(
                    url: url,
                    gitId: tag
                )
                var repositoryPath = pluginCacheDirectory.appending(component: PluginServiceConstants.repository)
                if let directory {
                    repositoryPath = repositoryPath.appending(try RelativePath(validating: directory))
                }
                let releasePath = pluginCacheDirectory.appending(component: PluginServiceConstants.release)
                return RemotePluginPaths(
                    repositoryPath: repositoryPath,
                    releasePath: try await fileSystem.exists(releasePath) ? releasePath : nil
                )
            }
        }
    }

    public func loadPlugins(using configGeneratedProjectsOptions: TuistGeneratedProjectOptions) async throws -> Plugins {
        guard !configGeneratedProjectsOptions.plugins.isEmpty else { return .none }

        try await fetchRemotePlugins(using: configGeneratedProjectsOptions)

        let localPluginPaths: [AbsolutePath] = try configGeneratedProjectsOptions.plugins
            .compactMap { pluginLocation in
                switch pluginLocation {
                case let .local(path):
                    Logger.current.debug("Using plugin \(pluginLocation.description)", metadata: .subsection)
                    return try AbsolutePath(validating: path)
                case .git:
                    return nil
                }
            }
        let localPluginManifests = try await localPluginPaths
            .concurrentMap { try await manifestLoader.loadPlugin(at: $0) }

        let remotePluginPaths = try await remotePluginPaths(using: configGeneratedProjectsOptions)
        let remotePluginRepositoryPaths = remotePluginPaths.map(\.repositoryPath)
        let remotePluginManifests = try await remotePluginRepositoryPaths
            .concurrentMap { try await manifestLoader.loadPlugin(at: $0) }
        let pluginPaths = localPluginPaths + remotePluginRepositoryPaths
        let missingRemotePlugins = try await zip(remotePluginManifests, remotePluginRepositoryPaths)
            .map { $0 }
            .concurrentFilter { try await !fileSystem.exists($0.1) }
        if !missingRemotePlugins.isEmpty {
            throw PluginServiceError.missingRemotePlugins(missingRemotePlugins.map(\.0.name))
        }

        let localProjectDescriptionHelperPlugins = try await zip(localPluginManifests, localPluginPaths)
            .concurrentCompactMap { plugin, path -> ProjectDescriptionHelpersPlugin? in
                try await projectDescriptionHelpersPlugin(name: plugin.name, pluginPath: path, location: .local)
            }

        let remoteProjectDescriptionHelperPlugins = try await zip(remotePluginManifests, remotePluginRepositoryPaths)
            .concurrentCompactMap { plugin, path -> ProjectDescriptionHelpersPlugin? in
                try await projectDescriptionHelpersPlugin(name: plugin.name, pluginPath: path, location: .remote)
            }

        let templatePaths = try await pluginPaths.concurrentFlatMap(templatePaths(pluginPath:))
        let resourceSynthesizerPlugins = try await zip(
            (localPluginManifests + remotePluginManifests).map(\.name),
            pluginPaths
                .map { $0.appending(component: Constants.resourceSynthesizersDirectoryName) }
        )
        .map { $0 }
        .concurrentFilter { _, path in try await fileSystem.exists(path) }
        .map(PluginResourceSynthesizer.init)

        return Plugins(
            projectDescriptionHelpers: localProjectDescriptionHelperPlugins + remoteProjectDescriptionHelperPlugins,
            templatePaths: templatePaths,
            resourceSynthesizers: resourceSynthesizerPlugins
        )
    }

    func fetchRemotePlugins(using configGeneratedProjectsOptions: TuistGeneratedProjectOptions) async throws {
        for pluginLocation in configGeneratedProjectsOptions.plugins {
            switch pluginLocation {
            case let .git(url, gitReference, _, releaseUrl):
                try await fetchRemotePlugin(
                    url: url,
                    releaseUrl: releaseUrl,
                    gitReference: gitReference,
                    configGeneratedProjectsOptions: configGeneratedProjectsOptions
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
        configGeneratedProjectsOptions _: TuistGeneratedProjectOptions
    ) async throws {
        let pluginCacheDirectory = try pluginCacheDirectory(
            url: url,
            gitId: gitReference.raw
        )
        try await fetchGitPluginRepository(
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
        gitId: String
    ) throws -> AbsolutePath {
        let cacheDirectory = try cacheDirectoriesProvider.cacheDirectory(for: .plugins)
        let fingerprint = "\(url)-\(gitId)".md5
        return cacheDirectory
            .appending(component: fingerprint)
    }

    /// Fetches the git plugins from the remote server and caches them in
    /// the Tuist cache with a unique fingerprint
    private func fetchGitPluginRepository(pluginCacheDirectory: AbsolutePath, url: String, gitId: String) async throws {
        let pluginRepositoryDirectory = pluginCacheDirectory.appending(component: PluginServiceConstants.repository)

        guard try await !fileSystem.exists(pluginRepositoryDirectory) else {
            Logger.current.debug("Using cached git plugin \(url)")
            return
        }

        Logger.current.notice("Cloning plugin from \(url) @ \(gitId)", metadata: .subsection)
        Logger.current.notice("\(pluginRepositoryDirectory.pathString)", metadata: .subsection)
        try gitController.clone(url: url, to: pluginRepositoryDirectory)
        try gitController.checkout(id: gitId, in: pluginRepositoryDirectory)
    }

    private func fetchGitPluginRelease(
        pluginCacheDirectory: AbsolutePath,
        url: String,
        gitTag: String,
        releaseUrl: String?
    ) async throws {
        let pluginRepositoryDirectory = pluginCacheDirectory.appending(component: PluginServiceConstants.repository)
        // If `Package.swift` exists for the plugin, a Github release should for the given `gitTag` should also exist
        guard try await fileSystem
            .exists(pluginRepositoryDirectory.appending(component: Constants.SwiftPackageManager.packageSwiftName))
        else { return }

        let pluginReleaseDirectory = pluginCacheDirectory.appending(component: PluginServiceConstants.release)
        guard try await !fileSystem.exists(pluginReleaseDirectory) else {
            Logger.current.debug("Using cached git plugin release \(url)")
            return
        }

        let plugin = try await manifestLoader.loadPlugin(at: pluginRepositoryDirectory)
        guard let releaseURL = getPluginDownloadUrl(gitUrl: url, gitTag: gitTag, pluginName: plugin.name, releaseUrl: releaseUrl)
        else { throw PluginServiceError.invalidURL(url) }

        Logger.current.debug("Cloning plugin release from \(url) @ \(gitTag)")
        try await FileHandler.shared.inTemporaryDirectory { _ in
            // Download the release.
            // Currently, we assume the release path exists.
            let downloadPath = try await fileClient.download(url: releaseURL)
            let downloadZipPath = downloadPath.removingLastComponent().appending(component: "release.zip")
            let fileUnarchiver = try fileArchivingFactory.makeFileUnarchiver(for: downloadZipPath)

            var thrownError: Error?

            do {
                if try await fileSystem.exists(downloadZipPath) {
                    try await fileSystem.remove(downloadZipPath)
                }
                try await fileSystem.move(from: downloadPath, to: downloadZipPath)

                // Unzip
                let unarchivedContents = try FileHandler.shared.contentsOfDirectory(
                    try fileUnarchiver.unzip()
                )

                try FileHandler.shared.createFolder(pluginReleaseDirectory)
                for unarchivedContent in unarchivedContents {
                    try await fileSystem.move(
                        from: unarchivedContent,
                        to: pluginReleaseDirectory.appending(component: unarchivedContent.basename)
                    )
                }

                // Mark files as executables (this information is lost during (un)archiving)
                try FileHandler.shared.contentsOfDirectory(pluginReleaseDirectory)
                    .filter { $0.basename.hasPrefix("tuist-") }
                    .forEach {
                        try System.shared.chmod(.executable, path: $0, options: [.onlyFiles])
                    }
            } catch {
                thrownError = error
            }

            try? await fileUnarchiver.delete()
            try? await fileSystem.remove(downloadPath)
            try? await fileSystem.remove(downloadZipPath)

            if let thrownError { throw thrownError }
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
    ) async throws -> ProjectDescriptionHelpersPlugin? {
        let helpersPath = pluginPath.appending(component: Constants.helpersDirectoryName)
        guard try await fileSystem.exists(helpersPath) else { return nil }
        return ProjectDescriptionHelpersPlugin(name: name, path: helpersPath, location: location)
    }

    private func templatePaths(
        pluginPath: AbsolutePath
    ) async throws -> [AbsolutePath] {
        let templatesPath = pluginPath.appending(component: Constants.templatesDirectoryName)
        guard try await fileSystem.exists(templatesPath) else { return [] }
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

#if DEBUG
    public final class MockPluginService: PluginServicing {
        public init() {}

        public var loadPluginsStub: (TuistGeneratedProjectOptions) -> Plugins = { _ in .none }
        public func loadPlugins(using config: TuistGeneratedProjectOptions) throws -> Plugins {
            loadPluginsStub(config)
        }

        public var fetchRemotePluginsStub: ((TuistGeneratedProjectOptions) throws -> Void)?
        public func fetchRemotePlugins(using config: TuistGeneratedProjectOptions) throws {
            try fetchRemotePluginsStub?(config)
        }

        public var remotePluginPathsStub: ((TuistGeneratedProjectOptions) throws -> [RemotePluginPaths])?
        public func remotePluginPaths(using config: TuistGeneratedProjectOptions) throws -> [RemotePluginPaths] {
            try remotePluginPathsStub?(config) ?? []
        }
    }
#endif
