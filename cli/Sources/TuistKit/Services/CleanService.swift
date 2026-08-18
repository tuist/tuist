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
}

struct CleanService {
    private let rootDirectoryLocator: RootDirectoryLocating
    private let cacheDirectoriesProvider: CacheDirectoriesProviding
    private let manifestFilesLocator: ManifestFilesLocating
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let cleanCacheService: CleanCacheServicing
    private let cleanProjectCacheService: CleanProjectCacheServicing
    private let getCacheEndpointsService: GetCacheEndpointsServicing
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let swiftPackageManagerScratchDirectoryLocator: SwiftPackageManagerScratchDirectoryLocator
    private let cacheDirectoryLock: CacheDirectoryLocking
    private let fileSystem: FileSystem

    init(
        rootDirectoryLocator: RootDirectoryLocating,
        cacheDirectoriesProvider: CacheDirectoriesProviding,
        manifestFilesLocator: ManifestFilesLocating,
        configLoader: ConfigLoading,
        serverEnvironmentService: ServerEnvironmentServicing,
        cleanCacheService: CleanCacheServicing,
        cleanProjectCacheService: CleanProjectCacheServicing,
        getCacheEndpointsService: GetCacheEndpointsServicing,
        serverAuthenticationController: ServerAuthenticationControlling,
        swiftPackageManagerScratchDirectoryLocator: SwiftPackageManagerScratchDirectoryLocator =
            SwiftPackageManagerScratchDirectoryLocator(),
        cacheDirectoryLock: CacheDirectoryLocking,
        fileSystem: FileSystem
    ) {
        self.rootDirectoryLocator = rootDirectoryLocator
        self.cacheDirectoriesProvider = cacheDirectoriesProvider
        self.manifestFilesLocator = manifestFilesLocator
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.cleanCacheService = cleanCacheService
        self.cleanProjectCacheService = cleanProjectCacheService
        self.getCacheEndpointsService = getCacheEndpointsService
        self.serverAuthenticationController = serverAuthenticationController
        self.swiftPackageManagerScratchDirectoryLocator = swiftPackageManagerScratchDirectoryLocator
        self.cacheDirectoryLock = cacheDirectoryLock
        self.fileSystem = fileSystem
    }

    init() {
        self.init(
            rootDirectoryLocator: RootDirectoryLocator(),
            cacheDirectoriesProvider: CacheDirectoriesProvider(),
            manifestFilesLocator: ManifestFilesLocator(),
            configLoader: ConfigLoader(),
            serverEnvironmentService: ServerEnvironmentService(),
            cleanCacheService: CleanCacheService(),
            cleanProjectCacheService: CleanProjectCacheService(),
            getCacheEndpointsService: GetCacheEndpointsService(),
            serverAuthenticationController: ServerAuthenticationController(),
            swiftPackageManagerScratchDirectoryLocator: SwiftPackageManagerScratchDirectoryLocator(),
            cacheDirectoryLock: CacheDirectoryLock(),
            fileSystem: FileSystem()
        )
    }

    func run(
        categories: [TuistCleanCategory],
        remote: Bool,
        path: String?
    ) async throws {
        let resolvedPath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let packageDirectory = try await manifestFilesLocator.locatePackageManifest(at: resolvedPath)?.parentDirectory
        let swiftPackageManagerScratchDirectory = try await swiftPackageManagerScratchDirectory(
            packageDirectory: packageDirectory,
            path: resolvedPath
        )

        for category in categories {
            try await clean(
                category,
                swiftPackageManagerScratchDirectory: swiftPackageManagerScratchDirectory
            )
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

    private func clean(
        _ category: TuistCleanCategory,
        swiftPackageManagerScratchDirectory: AbsolutePath?
    ) async throws {
        let cleaned: Bool
        let directory: AbsolutePath?
        switch category {
        case let .global(category):
            let globalDirectory = try cacheDirectoriesProvider.cacheDirectory(for: category)
            directory = globalDirectory
            cleaned = try await cacheDirectoryLock.whileEmptying(category) {
                try await emptyShared(globalDirectory)
            }
        case .dependencies:
            directory = swiftPackageManagerScratchDirectory
            // Neither locked nor emptied through `emptyShared`: the scratch directory belongs to a
            // single checkout, so no other process on the host resolves paths inside it, and the
            // staging directory `emptyShared` leaves behind while it deletes would sit in the
            // user's project rather than in a directory Tuist owns.
            if let scratchDirectory = swiftPackageManagerScratchDirectory,
               try await fileSystem.exists(scratchDirectory)
            {
                try await fileSystem.remove(scratchDirectory)
                try await fileSystem.makeDirectory(at: scratchDirectory)
                cleaned = true
            } else {
                cleaned = false
            }
        }
        if cleaned, let directory {
            AlertController.current
                .success(.alert("Successfully cleaned artifacts at path \(directory.pathString)"))
        } else {
            Logger.current.notice("There's nothing to clean for \(category.defaultValueDescription)")
        }
    }

    /// Empties a cache directory that every Tuist process on the host shares, and reports whether
    /// there was anything to empty.
    ///
    /// The contents are moved aside and the moved copy is deleted, rather than the directory being
    /// deleted where it stands. Deleting in place leaves the path missing for as long as the
    /// recursive delete of a warm cache takes, which is long enough that a command running
    /// alongside this one resolves a path inside it and fails: a manifest write into
    /// `Manifests` is the one that reaches users, as a rename onto a directory that no longer
    /// exists. A move is a single rename, so the path is missing only between the move and the
    /// call that recreates it.
    ///
    /// A move that finds nothing to move produces the outcome this method is asked for, so it
    /// reports nothing cleaned rather than failing. That covers both a cache that was never
    /// populated and a concurrent `tuist clean` that emptied this directory first, which is the
    /// interleaving that used to surface as `Path not found` naming a cache directory.
    private func emptyShared(_ directory: AbsolutePath) async throws -> Bool {
        let stagingDirectory = directory.parentDirectory
            .appending(component: "\(directory.basename).\(UUID().uuidString).deleting")
        do {
            try await fileSystem.move(from: directory, to: stagingDirectory)
        } catch FileSystemError.moveNotFound {
            return false
        }
        try await fileSystem.makeDirectory(at: directory, options: [.createTargetParentDirectories])
        try await fileSystem.remove(stagingDirectory)
        return true
    }

    private func swiftPackageManagerScratchDirectory(
        packageDirectory: AbsolutePath?,
        path: AbsolutePath
    ) async throws -> AbsolutePath? {
        guard let packageDirectory else { return nil }

        let config = try await configLoader.loadConfig(path: path)
        let arguments = config.project.generatedProject?.installOptions.passthroughSwiftPackageManagerArguments ?? []
        return try swiftPackageManagerScratchDirectoryLocator.locate(
            packagePath: packageDirectory,
            arguments: arguments,
            environment: Environment.current.variables,
            workingDirectory: try await Environment.current.currentWorkingDirectory()
        )
    }
}
