import Foundation
import TuistCore
import TuistSupport

struct CloudHEADResponse: Decodable {
    public static func existsResource(hash: String, config: Config) throws -> HTTPResource<CloudResponse<CloudHEADResponse>, CloudResponseError> {
        let url = try URL.apiCacheURL(hash: hash, config: config)
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        return .jsonResource { request }
    }
}
