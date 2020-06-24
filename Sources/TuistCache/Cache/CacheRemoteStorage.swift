import Foundation
import RxSwift
import TSCBasic
import TuistCore
import TuistSupport

// TODO: Later, add a warmup function to check if it's correctly authenticated ONCE
final class CacheRemoteStorage: CacheStoring {
    // MARK: - Attributes

    private let cloudClient: CloudClienting
    private let fileUploader: FileUploading
    private let fileArchiver: FileArchiving
    private let fileHandler: FileHandling

    // MARK: - Init

    init(cloudClient: CloudClienting,
         fileArchiver: FileArchiving = FileArchiver(),
         fileUploader: FileUploading = FileUploader(),
         fileHandler: FileHandling = FileHandler()) {
        self.cloudClient = cloudClient
        self.fileArchiver = fileArchiver
        self.fileUploader = fileUploader
        self.fileHandler = fileHandler
    }

    // MARK: - CacheStoring

    func exists(hash: String, config: Config) -> Single<Bool> {
        do {
            let successRange = 200 ..< 300
            let resource = try CloudHEADResponse.existsResource(hash: hash, config: config)
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

    func fetch(hash: String, config: Config) -> Single<AbsolutePath> {
        do {
            let resource = try CloudCacheResponse.fetchResource(hash: hash, config: config)
            return cloudClient.request(resource).map { _ in
                AbsolutePath.root // TODO:
            }
        } catch {
            return Single.error(error)
        }
    }

    func store(hash: String, config: Config, xcframeworkPath: AbsolutePath) -> Completable {
        do {
            let destinationZipPath = try fileArchiver.zip(xcframeworkPath: xcframeworkPath, hash: hash)
            let resource = try CloudCacheResponse.storeResource(
                hash: hash,
                config: config,
                contentMD5: try fileHandler.base64MD5(path: destinationZipPath)
            )

            return cloudClient
                .request(resource)
                .map { (responseTuple) -> URL in responseTuple.object.data.url }
                .flatMapCompletable { (url: URL) in
                    self.fileUploader.upload(file: destinationZipPath, hash: hash, to: url).asCompletable()
                }
        } catch {
            return Completable.error(error)
        }
    }
}
