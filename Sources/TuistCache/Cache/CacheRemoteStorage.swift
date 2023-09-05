import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import TuistCloud

enum CacheRemoteStorageError: FatalError, Equatable {
    case artifactNotFound(hash: String)

    var type: ErrorType {
        switch self {
        case .artifactNotFound: return .abort
        }
    }

    var description: String {
        switch self {
        case let .artifactNotFound(hash):
            return "The downloaded artifact with hash '\(hash)' has an incorrect format and doesn't contain xcframework, framework or bundle."
        }
    }
}

// TODO: Later, add a warmup function to check if it's correctly authenticated ONCE
public final class CacheRemoteStorage: CacheStoring {
    // MARK: - Attributes

    private let cloudConfig: Cloud
    private let fileClient: FileClienting
    private let fileArchiverFactory: FileArchivingFactorying
    private let cacheDirectoriesProvider: CacheDirectoriesProviding
    private let cacheExistsService: CacheExistsServicing
    private let getCacheService: GetCacheServicing
    private let uploadCacheService: UploadCacheServicing
    private let verifyCacheUploadService: VerifyCacheUploadServicing

    // MARK: - Init

    public init(
        cloudConfig: Cloud,
        fileArchiverFactory: FileArchivingFactorying = FileArchivingFactory(),
        fileClient: FileClienting = FileClient(),
        cacheDirectoriesProvider: CacheDirectoriesProviding,
        cacheExistsService: CacheExistsServicing = CacheExistsService(),
        getCacheService: GetCacheServicing = GetCacheService(),
        uploadCacheService: UploadCacheServicing = UploadCacheService(),
        verifyCacheUploadService: VerifyCacheUploadServicing = VerifyCacheUploadService()
    ) {
        self.cloudConfig = cloudConfig
        self.fileArchiverFactory = fileArchiverFactory
        self.fileClient = fileClient
        self.cacheDirectoriesProvider = cacheDirectoriesProvider
        self.cacheExistsService = cacheExistsService
        self.getCacheService = getCacheService
        self.uploadCacheService = uploadCacheService
        self.verifyCacheUploadService = verifyCacheUploadService
    }

    // MARK: - CacheStoring

    public func exists(name: String, hash: String) async throws -> Bool {
        do {
            try await cacheExistsService.cacheExists(
                serverURL: cloudConfig.url,
                projectId: cloudConfig.projectId,
                hash: hash,
                name: name
            )
        } catch let error as CacheExistsServiceError {
            switch error {
            case .notFound:
                return false
            default:
                throw error
            }
        }
        
        return true
    }

    public func fetch(name: String, hash: String) async throws -> AbsolutePath {
        let cacheArtifact = try await getCacheService.getCache(
            serverURL: cloudConfig.url,
            projectId: cloudConfig.projectId,
            hash: hash,
            name: name
        )

        logger.info("Downloading cache artifact for target \(name) with hash \(hash).")
        let filePath = try await fileClient.download(url: cacheArtifact.url)
        return try unzip(downloadedArchive: filePath, hash: hash)
    }

    public func store(name: String, hash: String, paths: [AbsolutePath]) async throws {
        let archiver = try fileArchiverFactory.makeFileArchiver(for: paths)
        do {
            let destinationZipPath = try archiver.zip(name: hash)
            let md5 = try FileHandler.shared.urlSafeBase64MD5(path: destinationZipPath)
            let url = try await uploadCacheService.uploadCache(
                serverURL: cloudConfig.url,
                projectId: cloudConfig.projectId,
                hash: hash,
                name: name,
                contentMD5: md5
            ).url

            _ = try await fileClient.upload(file: destinationZipPath, hash: hash, to: url)

            try await verifyCacheUploadService.verifyCacheUpload(
                serverURL: cloudConfig.url,
                projectId: cloudConfig.projectId,
                hash: hash,
                name: name,
                contentMD5: md5
            )
        } catch {
            try archiver.delete()
            throw error
        }
    }

    // MARK: - Private

    private func artifactPath(in archive: AbsolutePath) -> AbsolutePath? {
        if let xcframeworkPath = FileHandler.shared.glob(archive, glob: "*.xcframework").first {
            return xcframeworkPath
        } else if let frameworkPath = FileHandler.shared.glob(archive, glob: "*.framework").first {
            return frameworkPath
        } else if let bundlePath = FileHandler.shared.glob(archive, glob: "*.bundle").first {
            return bundlePath
        }
        return nil
    }

    private func unzip(downloadedArchive: AbsolutePath, hash: String) throws -> AbsolutePath {
        let zipPath = try FileHandler.shared.changeExtension(path: downloadedArchive, to: "zip")
        let archiveDestination = cacheDirectoriesProvider.cacheDirectory(for: .builds).appending(component: hash)
        let fileUnarchiver = try fileArchiverFactory.makeFileUnarchiver(for: zipPath)
        let unarchivedDirectory = try fileUnarchiver.unzip()
        defer {
            try? fileUnarchiver.delete()
        }
        if artifactPath(in: unarchivedDirectory) == nil {
            throw CacheRemoteStorageError.artifactNotFound(hash: hash)
        }
        if !FileHandler.shared.exists(archiveDestination.parentDirectory) {
            try FileHandler.shared.createFolder(archiveDestination.parentDirectory)
        }
        try FileHandler.shared.move(from: unarchivedDirectory, to: archiveDestination)
        return artifactPath(in: archiveDestination)!
    }
}
