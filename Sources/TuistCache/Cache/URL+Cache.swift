import Foundation

extension URL {
    static func apiCacheURL(hash: String,
                            cacheURL: URL,
                            projectId: String,
                            contentMD5: String? = nil) throws -> URL
    {
        guard var urlComponents = URLComponents(url: cacheURL, resolvingAgainstBaseURL: false) else {
            throw CacheAPIError.incorrectCloudURL
        }

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "project_id", value: projectId),
            URLQueryItem(name: "hash", value: hash)
        ]
        if let contentMD5 = contentMD5 {
            queryItems.append(URLQueryItem(name: "content_md5", value: contentMD5))
        }

        urlComponents.path = "/api/cache"
        urlComponents.queryItems = queryItems
        return urlComponents.url!
    }

    static func apiCacheVerifyUploadURL(hash: String,
                                        cacheURL: URL,
                                        projectId: String,
                                        contentMD5: String) throws -> URL
    {
        guard var urlComponents = URLComponents(url: cacheURL, resolvingAgainstBaseURL: false) else {
            throw CacheAPIError.incorrectCloudURL
        }

        urlComponents.path = "/api/cache/verify_upload"
        urlComponents.queryItems = [
            URLQueryItem(name: "project_id", value: projectId),
            URLQueryItem(name: "hash", value: hash),
            URLQueryItem(name: "content_md5", value: contentMD5)
        ]
        return urlComponents.url!
    }
}
