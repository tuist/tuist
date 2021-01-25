import Foundation
import TuistCore
import TuistGraph
import TuistSupport

struct CloudHEADResponse: Decodable {
    public init() {}

    public static func existsResource(hash: String, cloud: Cloud) throws -> HTTPResource<CloudResponse<CloudHEADResponse>, CloudHEADResponseError> {
        let url = try URL.apiCacheURL(hash: hash, cacheURL: cloud.url, projectId: cloud.projectId)
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        return HTTPResource(request: { request },
                            parse: { _, _ in CloudResponse(status: "HEAD", data: CloudHEADResponse()) },
                            parseError: { _, _ in CloudHEADResponseError() })
    }
}
