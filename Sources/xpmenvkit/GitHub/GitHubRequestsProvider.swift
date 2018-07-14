import Foundation

class GitHubRequestsProvider {
    /// MARK: - Constants

    /// Releases repository.
    static let releasesRepository: String = "xcode-project-manager/releases"

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
        let path = "/repos/\(GitHubRequestsProvider.releasesRepository)/releases"
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return request
    }
}
