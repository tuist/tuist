import Foundation

extension URL {
    static func apiCacheURL(hash: String,
                            cacheURL: URL,
                            projectId: String) throws -> URL
    {
        guard var urlComponents = URLComponents(url: cacheURL, resolvingAgainstBaseURL: false) else {
            throw CacheAPIError.incorrectScaleURL
        }

        urlComponents.path = "/api/cache"
        urlComponents.queryItems = [
            URLQueryItem(name: "project_id", value: projectId),
            URLQueryItem(name: "hash", value: hash),
        ]
        return urlComponents.url!
    }

    func addingQueryItem(name: String, value: String) -> URL {
        var urlComponents = URLComponents(url: self, resolvingAgainstBaseURL: false)!

        var existingQueryItems = urlComponents.queryItems ?? [URLQueryItem]()
        existingQueryItems.append(URLQueryItem(name: name, value: value))
        urlComponents.queryItems = existingQueryItems

        return urlComponents.url!
    }
}
