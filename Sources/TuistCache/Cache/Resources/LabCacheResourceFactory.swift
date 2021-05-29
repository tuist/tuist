import Foundation
import TuistCore
import TuistGraph
import TuistSupport

typealias LabExistsResource = HTTPResource<LabResponse<LabHEADResponse>, LabHEADResponseError>
typealias LabCacheResource = HTTPResource<LabResponse<LabCacheResponse>, LabResponseError>
typealias LabVerifyUploadResource = HTTPResource<LabResponse<LabVerifyUploadResponse>, LabResponseError>

/// Entity responsible for providing cache-related resources
protocol LabCacheResourceFactorying {
    func existsResource(hash: String) throws -> LabExistsResource
    func fetchResource(hash: String) throws -> LabCacheResource
    func storeResource(hash: String, contentMD5: String) throws -> LabCacheResource
    func verifyUploadResource(hash: String, contentMD5: String) throws -> LabVerifyUploadResource
}

class LabCacheResourceFactory: LabCacheResourceFactorying {
    private let labConfig: Lab

    init(labConfig: Lab) {
        self.labConfig = labConfig
    }

    func existsResource(hash: String) throws -> LabExistsResource {
        let url = try apiCacheURL(hash: hash, cacheURL: labConfig.url, projectId: labConfig.projectId)
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        return HTTPResource(
            request: { request },
            parse: { _, _ in LabResponse(status: "HEAD", data: LabHEADResponse()) },
            parseError: { _, _ in LabHEADResponseError() }
        )
    }

    func fetchResource(hash: String) throws -> LabCacheResource {
        let url = try apiCacheURL(
            hash: hash,
            cacheURL: labConfig.url,
            projectId: labConfig.projectId
        )
        return HTTPResource.jsonResource(for: url, httpMethod: "GET")
    }

    func storeResource(hash: String, contentMD5: String) throws -> LabCacheResource {
        let url = try apiCacheURL(
            hash: hash,
            cacheURL: labConfig.url,
            projectId: labConfig.projectId,
            contentMD5: contentMD5
        )
        return HTTPResource.jsonResource(for: url, httpMethod: "POST")
    }

    func verifyUploadResource(hash: String, contentMD5: String) throws -> LabVerifyUploadResource {
        let url = try apiCacheVerifyUploadURL(
            hash: hash,
            cacheURL: labConfig.url,
            projectId: labConfig.projectId,
            contentMD5: contentMD5
        )
        return HTTPResource.jsonResource(for: url, httpMethod: "POST")
    }

    // MARK: Private

    private func apiCacheURL(hash: String,
                             cacheURL: URL,
                             projectId: String,
                             contentMD5: String? = nil) throws -> URL
    {
        var urlComponents = URLComponents(url: cacheURL, resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "project_id", value: projectId),
            URLQueryItem(name: "hash", value: hash),
        ]
        if let contentMD5 = contentMD5 {
            queryItems.append(URLQueryItem(name: "content_md5", value: contentMD5))
        }

        urlComponents.path = "/api/cache"
        urlComponents.queryItems = queryItems
        return urlComponents.url!
    }

    private func apiCacheVerifyUploadURL(hash: String,
                                         cacheURL: URL,
                                         projectId: String,
                                         contentMD5: String) throws -> URL
    {
        var urlComponents = URLComponents(url: cacheURL, resolvingAgainstBaseURL: false)!
        urlComponents.path = "/api/cache/verify_upload"
        urlComponents.queryItems = [
            URLQueryItem(name: "project_id", value: projectId),
            URLQueryItem(name: "hash", value: hash),
            URLQueryItem(name: "content_md5", value: contentMD5),
        ]
        return urlComponents.url!
    }
}
