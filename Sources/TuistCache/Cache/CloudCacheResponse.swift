import Foundation
import TuistCore
import TuistGraph
import TuistSupport

struct CloudCacheResponse: Decodable {
    typealias CloudCacheResource = HTTPResource<CloudResponse<CloudCacheResponse>, CloudResponseError>

    let url: URL
    let expiresAt: TimeInterval
    let additionalHeaders: [String: String]?

    init(url: URL, expiresAt: TimeInterval, additionalHeaders: [String: String]? = nil) {
        self.url = url
        self.expiresAt = expiresAt
        self.additionalHeaders = additionalHeaders
    }

    public static func fetchResource(hash: String, targetName: String, cloud: Cloud) throws -> CloudCacheResource {
        var request = URLRequest(url: try URL.apiCacheURL(hash: hash, cacheURL: cloud.url, projectId: cloud.projectId, targetName: targetName))
        request.httpMethod = "GET"
        return .jsonResource { request }
    }

    public static func storeResource(hash: String, targetName: String, cloud: Cloud, contentMD5: String) throws -> CloudCacheResource {
        let url = try URL.apiCacheURL(hash: hash, cacheURL: cloud.url, projectId: cloud.projectId, targetName: targetName)
        var request = URLRequest(url: url.addingQueryItem(name: "content_md5", value: contentMD5))
        request.httpMethod = "POST"
        return .jsonResource { request }
    }
}
