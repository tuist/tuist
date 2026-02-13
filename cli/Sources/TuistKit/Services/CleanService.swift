import FileSystem
import Foundation
import Path
import TuistAlert
import TuistCache
import TuistConfigLoader
import TuistConstants
import TuistCore
import TuistEnvironment
import TuistLoader
import TuistLogging
import TuistRootDirectoryLocator
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

struct CleanService {
    private let fileHandler: FileHandling
    private let rootDirectoryLocator: RootDirectoryLocating
    private let cacheDirectoriesProvider: CacheDirectoriesProviding
    private let manifestFilesLocator: ManifestFilesLocating
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let cleanCacheService: CleanCacheServicing
    private let cleanProjectCacheService: CleanProjectCacheServicing
    private let getCacheEndpointsService: GetCacheEndpointsServicing
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let fileSystem: FileSystem

    init(
        fileHandler: FileHandling,
        rootDirectoryLocator: RootDirectoryLocating,
        cacheDirectoriesProvider: CacheDirectoriesProviding,
        manifestFilesLocator: ManifestFilesLocating,
        configLoader: ConfigLoading,
        serverEnvironmentService: ServerEnvironmentServicing,
        cleanCacheService: CleanCacheServicing,
        cleanProjectCacheService: CleanProjectCacheServicing,
        getCacheEndpointsService: GetCacheEndpointsServicing,
        serverAuthenticationController: ServerAuthenticationControlling,
        fileSystem: FileSystem
    ) {
        self.fileHandler = fileHandler
        self.rootDirectoryLocator = rootDirectoryLocator
        self.cacheDirectoriesProvider = cacheDirectoriesProvider
        self.manifestFilesLocator = manifestFilesLocator
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.cleanCacheService = cleanCacheService
        self.cleanProjectCacheService = cleanProjectCacheService
        self.getCacheEndpointsService = getCacheEndpointsService
        self.serverAuthenticationController = serverAuthenticationController
        self.fileSystem = fileSystem
    }

    init() {
        self.init(
            fileHandler: FileHandler.shared,
            rootDirectoryLocator: RootDirectoryLocator(),
            cacheDirectoriesProvider: CacheDirectoriesProvider(),
            manifestFilesLocator: ManifestFilesLocator(),
            configLoader: ConfigLoader(),
            serverEnvironmentService: ServerEnvironmentService(),
            cleanCacheService: CleanCacheService(),
            cleanProjectCacheService: CleanProjectCacheService(),
            getCacheEndpointsService: GetCacheEndpointsService(),
            serverAuthenticationController: ServerAuthenticationController(),
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
                AlertController.current
                    .success(.alert("Successfully cleaned artifacts at path \(directory.pathString)"))
            } else {
                Logger.current.notice("There's nothing to clean for \(category.defaultValueDescription)")
            }
        }

        if remote {
            let config = try await configLoader.loadConfig(path: resolvedPath)
            guard let fullHandle = config.fullHandle else { return }
            let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

            if Environment.current.isLegacyModuleCacheEnabled {
                try await cleanCacheService.cleanCache(
                    serverURL: serverURL,
                    fullHandle: fullHandle
                )
            } else {
                let handles = fullHandle.components(separatedBy: "/")
                guard handles.count == 2 else { return }
                let accountHandle = handles[0]
                let projectHandle = handles[1]

                let endpoints = try await getCacheEndpointsService.getCacheEndpoints(
                    serverURL: serverURL,
                    accountHandle: accountHandle
                )

                try await withThrowingTaskGroup(of: Void.self) { group in
                    for endpoint in endpoints {
                        guard let cacheURL = URL(string: endpoint) else { continue }
                        group.addTask {
                            try await cleanProjectCacheService.cleanProjectCache(
                                accountHandle: accountHandle,
                                projectHandle: projectHandle,
                                serverURL: cacheURL,
                                authenticationURL: serverURL,
                                serverAuthenticationController: serverAuthenticationController
                            )
                        }
                    }
                    try await group.waitForAll()
                }
            }

            Logger.current.notice("Successfully cleaned the remote storage.")
        }
    }
}
