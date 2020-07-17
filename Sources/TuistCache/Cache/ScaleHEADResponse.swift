import Foundation
import TuistCore
import TuistSupport

struct ScaleHEADResponse: Decodable {
    public init() {}

    public static func existsResource(hash: String, config: Config) throws -> HTTPResource<ScaleResponse<ScaleHEADResponse>, ScaleHEADResponseError> {
        guard let configScale = config.scale else { throw CacheAPIError.missingScaleConfig }
        let url = try URL.apiCacheURL(hash: hash, cacheURL: configScale.url, projectId: configScale.projectId)
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        return HTTPResource(request: { request },
                            parse: { _, _ in ScaleResponse(status: "HEAD", data: ScaleHEADResponse()) },
                            parseError: { _, _ in ScaleHEADResponseError() })
    }
}
