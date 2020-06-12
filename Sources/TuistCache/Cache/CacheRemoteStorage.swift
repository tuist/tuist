import Foundation
import RxSwift
import TSCBasic
import TuistCore
import TuistSupport

// TODO: Later, add a warmup function to check if it's correctly authenticated ONCE
final class CacheRemoteStorage: CacheStoring {
    // MARK: - Attributes

    private let cloudClient: CloudClienting

    // MARK: - Init

    init(cloudClient: CloudClienting) {
        self.cloudClient = cloudClient
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
            let resource = try CloudCacheResponse.storeResource(hash: hash, config: config)
            return cloudClient.request(resource).map { responseTuple in
                let cacheResponse = responseTuple.object.data
                let artefactToUploadURL = cacheResponse.url
                print(artefactToUploadURL)
                print("---")
                print(xcframeworkPath.pathString)
                // TODO: Download file at given url
            }.asCompletable()
        } catch {
            return Completable.error(error)
        }
    }
}
