import Foundation

class GitHubRequestsFactory {
    /// MARK: - Constants

    /// Releases repository.
    static let releasesRepository: String = "tuist/releases"

    // MARK: - Attributes

    /// Base URL used for requests.
    let baseURL: URL

    // MARK: - Init

    init(baseURL: URL = URL(string: "https://api.github.com")!) {
        self.baseURL = baseURL
    }

    /// Returns a request for fetching the project releases.
    ///
    /// - Returns: URLRequest to fetch the project releases.
    func releases() -> URLRequest {
        let path = "/repos/\(GitHubRequestsFactory.releasesRepository)/releases"
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return request
    }
}
