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

    public static func fetchResource(hash: String, config: Config) throws -> ScaleCacheResource {
        guard let configScale = config.scale else { throw CacheAPIError.missingScaleConfig }
        var request = URLRequest(url: try URL.apiCacheURL(hash: hash, cacheURL: configScale.url, projectId: configScale.projectId))
        request.httpMethod = "GET"
        return .jsonResource { request }
    }

    public static func storeResource(hash: String, config: Config, contentMD5: String) throws -> ScaleCacheResource {
        guard let configScale = config.scale else { throw CacheAPIError.missingScaleConfig }
        let url = try URL.apiCacheURL(hash: hash, cacheURL: configScale.url, projectId: configScale.projectId)
        var request = URLRequest(url: url.addingQueryItem(name: "content_md5", value: contentMD5))
        request.httpMethod = "POST"
        return .jsonResource { request }
    }
}
