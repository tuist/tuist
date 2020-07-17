import Foundation
import TuistCore
import TuistSupport

struct ScaleHEADResponse: Decodable {
    public init() {}

    public static func existsResource(hash: String, scale: Scale) throws -> HTTPResource<ScaleResponse<ScaleHEADResponse>, ScaleHEADResponseError> {
        let url = try URL.apiCacheURL(hash: hash, cacheURL: scale.url, projectId: scale.projectId)
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        return HTTPResource(request: { request },
                            parse: { _, _ in ScaleResponse(status: "HEAD", data: ScaleHEADResponse()) },
                            parseError: { _, _ in ScaleHEADResponseError() })
    }
}
