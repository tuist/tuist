import Foundation
import TuistCore
import TuistSupport

struct ScaleCacheResponse: Decodable {
    typealias ScaleCacheResource = HTTPResource<ScaleResponse<ScaleCacheResponse>, ScaleResponseError>

    let url: URL
    let expiresAt: TimeInterval

    init(url: URL, expiresAt: TimeInterval) {
        self.url = url
        self.expiresAt = expiresAt
    }

    public static func fetchResource(hash: String, scale: Scale) throws -> ScaleCacheResource {
        var request = URLRequest(url: try URL.apiCacheURL(hash: hash, cacheURL: scale.url, projectId: scale.projectId))
        request.httpMethod = "GET"
        return .jsonResource { request }
    }

    public static func storeResource(hash: String, scale: Scale, contentMD5: String) throws -> ScaleCacheResource {
        let url = try URL.apiCacheURL(hash: hash, cacheURL: scale.url, projectId: scale.projectId)
        var request = URLRequest(url: url.addingQueryItem(name: "content_md5", value: contentMD5))
        request.httpMethod = "POST"
        return .jsonResource { request }
    }
}
