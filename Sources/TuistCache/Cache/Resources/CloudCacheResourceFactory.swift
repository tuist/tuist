import Foundation
import TuistCore
import TuistGraph
import TuistSupport

typealias CloudExistsResource = HTTPResource<CloudResponse<CloudHEADResponse>, CloudHEADResponseError>

typealias CloudCacheResource = HTTPResource<CloudResponse<CloudCacheResponse>, CloudResponseError>

typealias CloudVerifyUploadResource = HTTPResource<CloudResponse<CloudVerifyUploadResponse>, CloudResponseError>

/// Entity responsible for providing cache-related resources
protocol CloudCacheResourceFactorying {
    func existsResource(hash: String) throws -> CloudExistsResource
    func fetchResource(hash: String) throws -> CloudCacheResource
    func storeResource(hash: String, contentMD5: String) throws -> CloudCacheResource
    func verifyUploadResource(hash: String, contentMD5: String) throws -> CloudVerifyUploadResource
}

class CloudCacheResourceFactory: CloudCacheResourceFactorying {
    private let cloudConfig: Cloud

    init(cloudConfig: Cloud) {
        self.cloudConfig = cloudConfig
    }

    func existsResource(hash: String) throws -> CloudExistsResource {
        let url = try apiCacheURL(hash: hash, cacheURL: cloudConfig.url, projectId: cloudConfig.projectId)
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        return HTTPResource(request: { request },
                            parse: { _, _ in CloudResponse(status: "HEAD", data: CloudHEADResponse()) },
                            parseError: { _, _ in CloudHEADResponseError() })
    }

    func fetchResource(hash: String) throws -> CloudCacheResource {
        let url = try apiCacheURL(
            hash: hash,
            cacheURL: cloudConfig.url,
            projectId: cloudConfig.projectId
        )
        return HTTPResource.jsonResource(for: url, httpMethod: "GET")
    }

    func storeResource(hash: String, contentMD5: String) throws -> CloudCacheResource {
        let url = try apiCacheURL(
            hash: hash,
            cacheURL: cloudConfig.url,
            projectId: cloudConfig.projectId,
            contentMD5: contentMD5
        )
        return HTTPResource.jsonResource(for: url, httpMethod: "POST")
    }

    func verifyUploadResource(hash: String, contentMD5: String) throws -> CloudVerifyUploadResource {
        let url = try apiCacheVerifyUploadURL(
            hash: hash,
            cacheURL: cloudConfig.url,
            projectId: cloudConfig.projectId,
            contentMD5: contentMD5
        )
        return HTTPResource.jsonResource(for: url, httpMethod: "POST")
    }

    // MARK: Private

    private func apiCacheURL(hash: String,
                             cacheURL: URL,
                             projectId: String,
                             contentMD5: String? = nil) throws -> URL
    {
        var urlComponents = URLComponents(url: cacheURL, resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "project_id", value: projectId),
            URLQueryItem(name: "hash", value: hash),
        ]
        if let contentMD5 = contentMD5 {
            queryItems.append(URLQueryItem(name: "content_md5", value: contentMD5))
        }

        urlComponents.path = "/api/cache"
        urlComponents.queryItems = queryItems
        return urlComponents.url!
    }

    private func apiCacheVerifyUploadURL(hash: String,
                                         cacheURL: URL,
                                         projectId: String,
                                         contentMD5: String) throws -> URL
    {
        var urlComponents = URLComponents(url: cacheURL, resolvingAgainstBaseURL: false)!
        urlComponents.path = "/api/cache/verify_upload"
        urlComponents.queryItems = [
            URLQueryItem(name: "project_id", value: projectId),
            URLQueryItem(name: "hash", value: hash),
            URLQueryItem(name: "content_md5", value: contentMD5),
        ]
        return urlComponents.url!
    }
}
