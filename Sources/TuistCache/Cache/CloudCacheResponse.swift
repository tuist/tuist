import Foundation
import TuistCore
import TuistSupport

struct CloudCacheResponse: Decodable {
    typealias CloudCacheResource = HTTPResource<CloudResponse<CloudCacheResponse>, CloudResponseError>

    let url: URL
    let expiresAt: TimeInterval

    init(url: URL, expiresAt: TimeInterval) {
        self.url = url
        self.expiresAt = expiresAt
    }

    public static func fetchResource(hash: String, config: Config) throws -> CloudCacheResource {
        guard let configCloud = config.cloud else { throw CacheAPIError.missingCloudConfig }
        var request = URLRequest(url: try URL.apiCacheURL(hash: hash, cloudURL: configCloud.url, projectId: configCloud.projectId))
        request.httpMethod = "GET"
        return .jsonResource { request }
    }

    public static func storeResource(hash: String, config: Config) throws -> CloudCacheResource {
        guard let configCloud = config.cloud else { throw CacheAPIError.missingCloudConfig }
        let url = try URL.apiCacheURL(hash: hash, cloudURL: configCloud.url, projectId: configCloud.projectId)
        var request = URLRequest(url: url.addingQueryItem(name: "content_md5", value: "TODO"))
        request.httpMethod = "POST"
        return .jsonResource { request }
    }
}
