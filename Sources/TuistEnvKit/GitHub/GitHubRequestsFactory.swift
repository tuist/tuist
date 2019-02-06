import Foundation

class GitHubRequestsFactory {
    // MARK: - Constants

    static let repository: String = "tuist/tuist"

    // MARK: - Attributes

    let baseURL: URL

    // MARK: - Init

    init(baseURL: URL = URL(string: "https://api.github.com")!) {
        self.baseURL = baseURL
    }

    func releases() -> URLRequest {
        let path = "/repos/\(GitHubRequestsFactory.repository)/releases"
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return request
    }

    func release(tag: String) -> URLRequest {
        let path = "/repos/\(GitHubRequestsFactory.repository)/releases/tags/\(tag)"
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return request
    }

    func getContent(ref: String, path: String) -> URLRequest {
        let path = "/repos/\(GitHubRequestsFactory.repository)/contents/\(path)"
        let url = baseURL.appendingPathComponent(path)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = []
        components.queryItems?.append(URLQueryItem(name: "ref", value: ref))
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        return request
    }
}
