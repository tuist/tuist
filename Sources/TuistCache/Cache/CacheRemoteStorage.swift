import Foundation
import TuistCloud
import RxSwift
import TuistSupport
import TSCBasic
import TuistCore

enum CacheRemoteStorageError: LocalizedError {
    case missingCloudConfig
    case incorrectCloudConfig
}

struct CloudHEADResponse: Decodable {}

// TODO: Later, aßdd a warmup function to check if it's correctly authenticated ONCE
final class CacheRemoteStorage: CacheStoring {
    // MARK: - Attributes
    
    private let cloudClient: CloudClienting
    
    // MARK: - Init
    
    init(cloudClient: CloudClienting) {
        self.cloudClient = cloudClient
    }
    
    // MARK: - CacheStoring
    
    func exists(hash: String, userConfig: Config) -> Single<Bool> {
        let resource = self.existsResource(hash: hash, userConfig: userConfig)
        return self.cloudClient.request(resource).map({ response in
            let successRange = 200..<300
            return successRange.contains(response.response.statusCode)
        })
    }
    
    func fetch(hash: String, userConfig: Config) -> Single<AbsolutePath> {
        let resource = self.fetchResource(hash: hash, userConfig: userConfig)
        return self.cloudClient.request(resource).map({ response in
            AbsolutePath.root // TODO
        })
    }
    
    func store(hash: String, userConfig: Config, xcframeworkPath: AbsolutePath) -> Completable {
        let resource = self.storeResource(hash: hash, userConfig: userConfig)
        return self.cloudClient.request(resource).map { responseTuple in
            let cacheResponse = responseTuple.object.data
            let artefactToDownloadURL = cacheResponse.url
            print(artefactToDownloadURL)
            // TODO: Download file at given url
        }.asCompletable()
    }
    
    // MARK: - Fileprivate
    
    fileprivate func apiCacheURL(hash: String, userConfig: Config, contentMD5: String? = nil) throws -> URL {
        guard let cloudConfig = userConfig.cloud else { throw CacheRemoteStorageError.missingCloudConfig }
        guard var urlComponents = URLComponents(url: cloudConfig.url, resolvingAgainstBaseURL: false) else {
            throw CacheRemoteStorageError.incorrectCloudConfig
        }
        
        urlComponents.path = "api/cache"
        var queryItems = [
            URLQueryItem(name: "project_id", value: cloudConfig.projectId),
            URLQueryItem(name: "hash", value: hash)
        ]
        
        if let contentMD5 = contentMD5 {
            queryItems.append(URLQueryItem(name: "content_md5", value: contentMD5))
        }
        
        urlComponents.queryItems = queryItems
        return urlComponents.url!
    }
    
    fileprivate func existsRequest(hash: String, userConfig: Config) throws -> URLRequest {
        var urlRequest = URLRequest(url: try apiCacheURL(hash: hash, userConfig: userConfig))
        urlRequest.httpMethod = "HEAD"
        return urlRequest
    }
    
    fileprivate func fetchRequest(hash: String, userConfig: Config) throws -> URLRequest {
        var urlRequest = URLRequest(url: try apiCacheURL(hash: hash, userConfig: userConfig))
        urlRequest.httpMethod = "GET"
        return urlRequest
    }
    
    fileprivate func storeRequest(hash: String, userConfig: Config) throws -> URLRequest {
        // TODO: Manage md5 hashing
        var urlRequest = URLRequest(url: try apiCacheURL(hash: hash, userConfig: userConfig, contentMD5: "TODO"))
        urlRequest.httpMethod = "POST"
        return urlRequest
    }
    
    fileprivate func existsResource(hash: String, userConfig: Config) -> HTTPResource<CloudResponse<CloudHEADResponse>, CloudResponseError> {
        let resource: HTTPResource<CloudResponse<CloudHEADResponse>, CloudResponseError> = .jsonResource { () -> URLRequest in
            try! self.existsRequest(hash: hash, userConfig: userConfig)
        }
        return resource
    }
    
    fileprivate func fetchResource(hash: String, userConfig: Config) -> HTTPResource<CloudResponse<CloudCacheResponse>, CloudResponseError> {
        let resource: HTTPResource<CloudResponse<CloudCacheResponse>, CloudResponseError> = .jsonResource { () -> URLRequest in
            try! self.fetchRequest(hash: hash, userConfig: userConfig)
        }
        return resource
    }
    
    fileprivate func storeResource(hash: String, userConfig: Config) -> HTTPResource<CloudResponse<CloudCacheResponse>, CloudResponseError> {
        let resource: HTTPResource<CloudResponse<CloudCacheResponse>, CloudResponseError> = .jsonResource { () -> URLRequest in
            try! self.storeRequest(hash: hash, userConfig: userConfig)
        }
        return resource
    }
}
