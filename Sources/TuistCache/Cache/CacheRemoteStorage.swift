import Foundation
import RxSwift
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

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

    private let cloudClient: CloudClienting
    private let fileClient: FileClienting
    private let fileArchiverFactory: FileArchivingFactorying
    private let cloudCacheResourceFactory: CloudCacheResourceFactorying
    private let cacheDirectoriesProvider: CacheDirectoriesProviding

    // MARK: - Init

    public convenience init(cloudConfig: Cloud, cloudClient: CloudClienting, cacheDirectoriesProvider: CacheDirectoriesProviding) {
        self.init(
            cloudClient: cloudClient,
            fileArchiverFactory: FileArchivingFactory(),
            fileClient: FileClient(),
            cloudCacheResourceFactory: CloudCacheResourceFactory(cloudConfig: cloudConfig),
            cacheDirectoriesProvider: cacheDirectoriesProvider
        )
    }

    init(cloudClient: CloudClienting,
         fileArchiverFactory: FileArchivingFactorying,
         fileClient: FileClienting,
         cloudCacheResourceFactory: CloudCacheResourceFactorying,
         cacheDirectoriesProvider: CacheDirectoriesProviding)
    {
        self.cloudClient = cloudClient
        self.fileArchiverFactory = fileArchiverFactory
        self.fileClient = fileClient
        self.cloudCacheResourceFactory = cloudCacheResourceFactory
        self.cacheDirectoriesProvider = cacheDirectoriesProvider
    }

    // MARK: - CacheStoring

    public func exists(name: String, hash: String) -> Single<Bool> {
        do {
            let successRange = 200 ..< 300
            let resource = try cloudCacheResourceFactory.existsResource(name: name, hash: hash)
            return cloudClient.request(resource)
                .flatMap { _, response in
                    .just(successRange.contains(response.statusCode))
                }
                .catchError { error in
                    if case let HTTPRequestDispatcherError.serverSideError(_, response) = error, response.statusCode == 404 {
                        return .just(false)
                    } else {
                        throw error
                    }
                }
        } catch {
            return Single.error(error)
        }
    }

    public func fetch(name: String, hash: String) -> Single<AbsolutePath> {
        do {
            let resource = try cloudCacheResourceFactory.fetchResource(name: name, hash: hash)
            return cloudClient
                .request(resource)
                .map(\.object.data.url)
                .flatMap { (url: URL) in
                    self.fileClient.download(url: url)
                        .do(onSubscribed: { logger.info("Downloading cache artifact with hash \(hash).") })
                }
                .flatMap { (filePath: AbsolutePath) in
                    do {
                        let archiveContentPath = try self.unzip(downloadedArchive: filePath, hash: hash)
                        return Single.just(archiveContentPath)
                    } catch {
                        return Single.error(error)
                    }
                }
        } catch {
            return Single.error(error)
        }
    }

    public func store(name: String, hash: String, paths: [AbsolutePath]) -> Completable {
        do {
            let archiver = try fileArchiverFactory.makeFileArchiver(for: paths)
            let destinationZipPath = try archiver.zip(name: hash)
            let md5 = try FileHandler.shared.urlSafeBase64MD5(path: destinationZipPath)
            let storeResource = try cloudCacheResourceFactory.storeResource(
                name: name,
                hash: hash,
                contentMD5: md5
            )

            return cloudClient
                .request(storeResource)
                .map { (responseTuple) -> URL in responseTuple.object.data.url }
                .flatMapCompletable { (url: URL) in
                    let deleteCompletable = self.deleteZipArchiveCompletable(archiver: archiver)
                    return self.fileClient.upload(file: destinationZipPath, hash: hash, to: url)
                        .flatMapCompletable { _ in
                            self.verify(name: name, hash: hash, contentMD5: md5)
                        }
                        .catchError {
                            deleteCompletable.concat(.error($0))
                        }
                }
        } catch {
            return Completable.error(error)
        }
    }

    // MARK: - Private

    private func verify(name: String, hash: String, contentMD5: String) -> Completable {
        do {
            let verifyUploadResource = try cloudCacheResourceFactory.verifyUploadResource(
                name: name,
                hash: hash,
                contentMD5: contentMD5
            )

            return cloudClient
                .request(verifyUploadResource).asCompletable()
        } catch {
            return Completable.error(error)
        }
    }

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

    private func deleteZipArchiveCompletable(archiver: FileArchiving) -> Completable {
        Completable.create(subscribe: { observer in
            do {
                try archiver.delete()
                observer(.completed)
            } catch {
                observer(.error(error))
            }
            return Disposables.create {}
        })
    }
}
