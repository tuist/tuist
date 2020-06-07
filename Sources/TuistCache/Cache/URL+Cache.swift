import Foundation
import TuistCore

enum CacheURLError: LocalizedError {
    case missingCloudConfig
    case incorrectCloudConfig
}

extension URL {
    static func apiCacheURL(hash: String, config: Config, contentMD5: String? = nil) throws -> URL {
        guard let cloudConfig = config.cloud else { throw CacheURLError.missingCloudConfig }
        guard var urlComponents = URLComponents(url: cloudConfig.url, resolvingAgainstBaseURL: false) else {
            throw CacheURLError.incorrectCloudConfig
        }

        urlComponents.path = "/api/cache"
        var queryItems = [
            URLQueryItem(name: "project_id", value: cloudConfig.projectId),
            URLQueryItem(name: "hash", value: hash),
        ]

        if let contentMD5 = contentMD5 {
            queryItems.append(URLQueryItem(name: "content_md5", value: contentMD5))
        }

        urlComponents.queryItems = queryItems
        return urlComponents.url!
    }
}
