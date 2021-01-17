import Foundation
import TuistCore
import TuistGraph
import TuistSupport

struct CloudCacheResponse: Decodable {
    typealias CloudCacheResource = HTTPResource<CloudResponse<CloudCacheResponse>, CloudResponseError>

    let url: URL
    let expiresAt: TimeInterval

    init(url: URL, expiresAt: TimeInterval) {
        self.url = url
        self.expiresAt = expiresAt
    }

    public static func fetchResource(hash: String, cloud: Cloud) throws -> CloudCacheResource {
        let url = try URL.apiCacheURL(
            hash: hash,
            cacheURL: cloud.url,
            projectId: cloud.projectId
        )
        return jsonResource(for: url, httpMethod: "GET")
    }

    public static func storeResource(hash: String,
                                     cloud: Cloud,
                                     contentMD5: String) throws -> CloudCacheResource {
        let url = try URL.apiCacheURL(
            hash: hash,
            cacheURL: cloud.url,
            projectId: cloud.projectId,
            contentMD5: contentMD5
        )
        return jsonResource(for: url, httpMethod: "POST")
    }

    public static func verifyUploadResource(hash: String,
                                            cloud: Cloud,
                                            contentMD5: String) throws -> CloudCacheResource {
        let url = try URL.apiCacheVerifyUploadURL(
            hash: hash,
            cacheURL: cloud.url,
            projectId: cloud.projectId,
            contentMD5: contentMD5
        )
        return jsonResource(for: url, httpMethod: "POST")
    }
    
    public static func jsonResource(for url: URL, httpMethod: String) -> CloudCacheResource {
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        return .jsonResource { request }
    }
}
