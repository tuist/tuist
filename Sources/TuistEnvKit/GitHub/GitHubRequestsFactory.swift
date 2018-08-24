import Foundation

class GitHubRequestsFactory {
    /// MARK: - Constants

    static let releasesRepository: String = "tuist/tuist"

    // MARK: - Attributes

    let baseURL: URL

    // MARK: - Init

    init(baseURL: URL = URL(string: "https://api.github.com")!) {
        self.baseURL = baseURL
    }

    func releases() -> URLRequest {
        let path = "/repos/\(GitHubRequestsFactory.releasesRepository)/releases"
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return request
    }

    func release(tag: String) -> URLRequest {
        let path = "/repos/\(GitHubRequestsFactory.releasesRepository)/releases/tags/\(tag)"
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return request
    }
}
