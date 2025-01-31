import FileSystem
import Foundation
import Path
import ServiceContextModule
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport

enum TuistCleanCategory: ExpressibleByArgument, CaseIterable, Equatable {
    static let allCases = CacheCategory.allCases
        .map { .global($0) } + [Self.dependencies]

    static var allValueStrings: [String] {
        TuistCleanCategory.allCases.map(\.defaultValueDescription)
    }

    /// The local global cache
    case global(CacheCategory)

    /// The local dependencies cache
    case dependencies

    var defaultValueDescription: String {
        switch self {
        case let .global(cacheCategory):
            return cacheCategory.rawValue
        case .dependencies:
            return "dependencies"
        }
    }

    init?(argument: String) {
        if let cacheCategory = CacheCategory(rawValue: argument) {
            self = .global(cacheCategory)
        } else if argument == "dependencies" {
            self = .dependencies
        } else {
            return nil
        }
    }

    func directory(
        packageDirectory: AbsolutePath?
    ) throws -> Path.AbsolutePath? {
        switch self {
        case let .global(category):
            return try CacheDirectoriesProvider().cacheDirectory(for: category)
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
    private let fileSystem: FileSystem

    init(
        fileHandler: FileHandling,
        rootDirectoryLocator: RootDirectoryLocating,
        cacheDirectoriesProvider: CacheDirectoriesProviding,
        manifestFilesLocator: ManifestFilesLocating,
        configLoader: ConfigLoading,
        serverURLService: ServerURLServicing,
        cleanCacheService: CleanCacheServicing,
        fileSystem: FileSystem
    ) {
        self.fileHandler = fileHandler
        self.rootDirectoryLocator = rootDirectoryLocator
        self.cacheDirectoriesProvider = cacheDirectoriesProvider
        self.manifestFilesLocator = manifestFilesLocator
        self.configLoader = configLoader
        self.serverURLService = serverURLService
        self.cleanCacheService = cleanCacheService
        self.fileSystem = fileSystem
    }

    public convenience init() {
        self.init(
            fileHandler: FileHandler.shared,
            rootDirectoryLocator: RootDirectoryLocator(),
            cacheDirectoriesProvider: CacheDirectoriesProvider(),
            manifestFilesLocator: ManifestFilesLocator(),
            configLoader: ConfigLoader(),
            serverURLService: ServerURLService(),
            cleanCacheService: CleanCacheService(),
            fileSystem: FileSystem()
        )
    }

    func run(
        categories: [TuistCleanCategory],
        remote: Bool,
        path: String?
    ) async throws {
        let resolvedPath = if let path {
            try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            FileHandler.shared.currentPath
        }

        let packageDirectory = try await manifestFilesLocator.locatePackageManifest(at: resolvedPath)?.parentDirectory

        for category in categories {
            let directory: AbsolutePath?
            switch category {
            case let .global(category):
                directory = try cacheDirectoriesProvider.cacheDirectory(for: category)
            case .dependencies:
                directory = packageDirectory?.appending(
                    component: Constants.SwiftPackageManager.packageBuildDirectoryName
                )
            }
            if let directory,
               try await fileSystem.exists(directory)
            {
                try await fileSystem.remove(directory)
                try await fileSystem.makeDirectory(at: directory)
                ServiceContext.current?.alerts?
                    .append(.success(.alert("Successfully cleaned artifacts at path \(directory.pathString)")))
            } else {
                ServiceContext.current?.logger?.notice("There's nothing to clean for \(category.defaultValueDescription)")
            }
        }

        if remote {
            let config = try await configLoader.loadConfig(path: resolvedPath)
            guard let fullHandle = config.fullHandle else { return }
            let serverURL = try serverURLService.url(configServerURL: config.url)
            try await cleanCacheService.cleanCache(
                serverURL: serverURL,
                fullHandle: fullHandle
            )

            ServiceContext.current?.logger?.notice("Successfully cleaned the remote storage.")
        }
    }
}
