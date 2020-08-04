import Foundation
import RxSwift
import TSCBasic
import TuistCore
import TuistSupport

enum CacheRemoteStorageError: FatalError, Equatable {
    case archiveDoesNotContainXCFramework(AbsolutePath)

    var type: ErrorType {
        switch self {
        case .archiveDoesNotContainXCFramework: return .abort
        }
    }

    var description: String {
        switch self {
        case let .archiveDoesNotContainXCFramework(path):
            return "Unzipped archive at path \(path.pathString) does not contain any xcframework."
        }
    }
}

// TODO: Later, add a warmup function to check if it's correctly authenticated ONCE
public final class CacheRemoteStorage: CacheStoring {
    // MARK: - Attributes

    private let scaleConfig: Scale
    private let scaleClient: ScaleClienting
    private let fileClient: FileClienting
    private let fileArchiverFactory: FileArchiverManufacturing
    private var fileArchiverMap: [AbsolutePath: FileArchiving] = [:]

    // MARK: - Init

    public convenience init(scaleConfig: Scale, scaleClient: ScaleClienting) {
        self.init(scaleConfig: scaleConfig,
                  scaleClient: scaleClient,
                  fileArchiverFactory: FileArchiverFactory(),
                  fileClient: FileClient())
    }

    init(scaleConfig: Scale,
         scaleClient: ScaleClienting,
         fileArchiverFactory: FileArchiverManufacturing,
         fileClient: FileClienting)
    {
        self.scaleConfig = scaleConfig
        self.scaleClient = scaleClient
        self.fileArchiverFactory = fileArchiverFactory
        self.fileClient = fileClient
    }

    // MARK: - CacheStoring

    public func exists(hash: String) -> Single<Bool> {
        do {
            let successRange = 200 ..< 300
            let resource = try ScaleHEADResponse.existsResource(hash: hash, scale: scaleConfig)
            return scaleClient.request(resource)
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

    public func fetch(hash: String) -> Single<AbsolutePath> {
        do {
            let resource = try ScaleCacheResponse.fetchResource(hash: hash, scale: scaleConfig)
            return scaleClient
                .request(resource)
                .map { $0.object.data.url }
                .flatMap { (url: URL) in self.fileClient.download(url: url) }
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

    public func store(hash: String, xcframeworkPath: AbsolutePath) -> Completable {
        do {
            let archiver = fileArchiver(for: xcframeworkPath)
            let destinationZipPath = try archiver.zip()
            let resource = try ScaleCacheResponse.storeResource(
                hash: hash,
                scale: scaleConfig,
                contentMD5: try FileHandler.shared.base64MD5(path: destinationZipPath)
            )

            return scaleClient
                .request(resource)
                .map { (responseTuple) -> URL in responseTuple.object.data.url }
                .flatMapCompletable { (url: URL) in
                    let deleteCompletable = self.deleteZipArchiveCompletable(archiver: archiver)
                    return self.fileClient.upload(file: destinationZipPath, hash: hash, to: url).asCompletable()
                        .andThen(deleteCompletable)
                        .catchError { deleteCompletable.concat(.error($0)) }
                }
        } catch {
            return Completable.error(error)
        }
    }

    // MARK: - Private

    private func xcframeworkPath(in archive: AbsolutePath) throws -> AbsolutePath? {
        let folderContent = try FileHandler.shared.contentsOfDirectory(archive)
        return folderContent.filter { FileHandler.shared.isFolder($0) && $0.extension == "xcframework" }.first
    }

    private func unzip(downloadedArchive: AbsolutePath, hash: String) throws -> AbsolutePath {
        let zipPath = try FileHandler.shared.changeExtension(path: downloadedArchive, to: "zip")
        let archiveDestination = Environment.shared.xcframeworksCacheDirectory.appending(component: hash)
        try fileArchiver(for: zipPath).unzip(to: archiveDestination)
        guard let xcframework = try xcframeworkPath(in: archiveDestination) else {
            try FileHandler.shared.delete(archiveDestination)
            throw CacheRemoteStorageError.archiveDoesNotContainXCFramework(archiveDestination)
        }
        return xcframework
    }

    private func fileArchiver(for path: AbsolutePath) -> FileArchiving {
        let fileArchiver = fileArchiverMap[path] ?? fileArchiverFactory.makeFileArchiver(for: path)
        fileArchiverMap[path] = fileArchiver
        return fileArchiver
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

    // MARK: - Deinit

    deinit {
        do {
            try fileArchiverMap.values.forEach { fileArchiver in try fileArchiver.delete() }
        } catch {}
    }
}
