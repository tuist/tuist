import Foundation
import Path
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import XcodeGraph

protocol CleanCategory: ExpressibleByArgument & CaseIterable {
    func directory(
        packageDirectory: AbsolutePath?,
        cacheDirectory: AbsolutePath
    ) throws -> AbsolutePath?
}

enum TuistCleanCategory: CleanCategory, Equatable {
    static let allCases = CacheCategory.App.allCases.map { .cloud($0) } + CacheCategory.allCases
        .map { .global($0) } + [Self.dependencies]

    static var allValueStrings: [String] {
        TuistCleanCategory.allCases.map(\.defaultValueDescription)
    }

    /// The global cache
    case global(CacheCategory)

    /// The global cloud cache
    case cloud(CacheCategory.App)

    /// The local dependencies cache
    case dependencies

    var defaultValueDescription: String {
        switch self {
        case let .global(cacheCategory):
            return cacheCategory.rawValue
        case let .cloud(cacheCategory):
            return cacheCategory.rawValue
        case .dependencies:
            return "dependencies"
        }
    }

    init?(argument: String) {
        if let cacheCategory = CacheCategory(rawValue: argument) {
            self = .global(cacheCategory)
        } else if let cacheCategory = CacheCategory.App(rawValue: argument) {
            self = .cloud(cacheCategory)
        } else if argument == "dependencies" {
            self = .dependencies
        } else {
            return nil
        }
    }

    func directory(
        packageDirectory: AbsolutePath?,
        cacheDirectory: AbsolutePath
    ) throws -> Path.AbsolutePath? {
        switch self {
        case let .global(category):
            return CacheDirectoriesProvider.tuistCacheDirectory(for: category, cacheDirectory: cacheDirectory)
        case let .cloud(category):
            return CacheDirectoriesProvider.tuistCloudCacheDirectory(
                for: category,
                cacheDirectory: cacheDirectory
            )
        case .dependencies:
            return packageDirectory?.appending(
                component: Constants.SwiftPackageManager.packageBuildDirectoryName
            )
        }
    }
}

final class CleanService {
    private let fileHandler: FileHandling
    private let rootDirectoryLocator: RootDirectoryLocating
    private let cacheDirectoriesProvider: CacheDirectoriesProviding
    private let manifestFilesLocator: ManifestFilesLocating
    private let configLoader: ConfigLoading
    private let serverURLService: ServerURLServicing
    private let cleanCacheService: CleanCacheServicing
    init(
        fileHandler: FileHandling,
        rootDirectoryLocator: RootDirectoryLocating,
        cacheDirectoriesProvider: CacheDirectoriesProviding,
        manifestFilesLocator: ManifestFilesLocating,
        configLoader: ConfigLoading,
        serverURLService: ServerURLServicing,
        cleanCacheService: CleanCacheServicing
    ) {
        self.fileHandler = fileHandler
        self.rootDirectoryLocator = rootDirectoryLocator
        self.cacheDirectoriesProvider = cacheDirectoriesProvider
        self.manifestFilesLocator = manifestFilesLocator
        self.configLoader = configLoader
        self.serverURLService = serverURLService
        self.cleanCacheService = cleanCacheService
    }

    public convenience init() {
        self.init(
            fileHandler: FileHandler.shared,
            rootDirectoryLocator: RootDirectoryLocator(),
            cacheDirectoriesProvider: CacheDirectoriesProvider(),
            manifestFilesLocator: ManifestFilesLocator(),
            configLoader: ConfigLoader(),
            serverURLService: ServerURLService(),
            cleanCacheService: CleanCacheService()
        )
    }

    func run(
        categories: [some CleanCategory],
        remote: Bool,
        path: String?
    ) async throws {
        let resolvedPath = if let path {
            try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            FileHandler.shared.currentPath
        }

        let cacheDirectory = try cacheDirectoriesProvider.cacheDirectory()
        let packageDirectory = manifestFilesLocator.locatePackageManifest(at: resolvedPath)?.parentDirectory

        for category in categories {
            if let directory = try category.directory(
                packageDirectory: packageDirectory,
                cacheDirectory: cacheDirectory
            ),
                fileHandler.exists(directory)
            {
                try FileHandler.shared.delete(directory)
                logger.notice("Successfully cleaned artifacts at path \(directory.pathString)", metadata: .success)
            } else {
                logger.notice("There's nothing to clean for \(category.defaultValueDescription)")
            }
        }

        if remote, let cloud = try configLoader.loadConfig(path: resolvedPath).cloud {
            let cloudURL = try serverURLService.url(configServerURL: cloud.url)
            try await cleanCacheService.cleanCache(
                serverURL: cloudURL,
                fullName: cloud.projectId
            )

            logger.notice("Successfully cleaned the remote storage.")
        }
    }
}
