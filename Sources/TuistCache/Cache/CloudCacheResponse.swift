import Foundation
import TuistCore
import TuistSupport

struct CloudCacheResponse: Decodable {
    let url: URL
    let expiresAt: TimeInterval

    init(url: URL, expiresAt: TimeInterval) {
        self.url = url
        self.expiresAt = expiresAt
    }
    
    public static func fetchResource(hash: String, config: Config) throws -> HTTPResource<CloudResponse<CloudCacheResponse>, CloudResponseError> {
        var request = URLRequest(url: try URL.apiCacheURL(hash: hash, config: config))
        request.httpMethod = "GET"
        return .jsonResource { request }
    }
    
    public static func storeResource(hash: String, config: Config) throws -> HTTPResource<CloudResponse<CloudCacheResponse>, CloudResponseError> {
        var request = URLRequest(url: try URL.apiCacheURL(hash: hash, config: config, contentMD5: "TODO"))
        request.httpMethod = "POST"
        return .jsonResource { request }
    }
}
