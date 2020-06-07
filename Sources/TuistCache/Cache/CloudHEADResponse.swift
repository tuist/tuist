import Foundation
import TuistCore
import TuistSupport

struct CloudHEADResponse: Decodable {
    public static func existsResource(hash: String, config: Config) throws -> HTTPResource<CloudResponse<CloudHEADResponse>, CloudResponseError> {
        var request = URLRequest(url: try URL.apiCacheURL(hash: hash, config: config))
        request.httpMethod = "HEAD"
        return .jsonResource { request }
    }
}
