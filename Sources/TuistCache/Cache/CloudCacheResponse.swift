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
        var request = URLRequest(url: try URL.apiCacheURL(hash: hash, cacheURL: cloud.url, projectId: cloud.projectId))
        request.httpMethod = "GET"
        return .jsonResource { request }
    }

    public static func storeResource(hash: String, cloud: Cloud, contentMD5: String) throws -> CloudCacheResource {
        let url = try URL.apiCacheURL(hash: hash, cacheURL: cloud.url, projectId: cloud.projectId)
        var request = URLRequest(url: url.addingQueryItem(name: "content_md5", value: contentMD5))
        request.httpMethod = "POST"
        return .jsonResource { request }
    }
}
