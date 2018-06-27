import Foundation

protocol GitHubClienting: AnyObject {
    func releases() throws -> [Release]
}

/// GitHub release.
struct Release {
    /// Release asset.
    struct Asset {
        let downloadURL: URL

        init?(json: [String: Any]) {
            guard let downloadURLString = json["browser_download_url"] as? String else { return nil }
            downloadURL = URL(string: downloadURLString)!
        }
    }

    /// Release id
    let id: Int

    /// Version
    let version: Version

    /// Name
    let name: String

    /// Body
    let body: String

    /// Release assets
    let assets: [Asset]

    init?(json: [String: Any]) {
        guard let versionString = json["tag_name"] as? String, let version = Version(string: versionString) else { return nil }
        guard let id = json["id"] as? Int else { return nil }
        guard let body = json["body"] as? String else { return nil }
        guard let name = json["name"] as? String else { return nil }
        guard let assets = json["assets"] as? [[String: Any]] else { return nil }
        self.id = id
        self.version = version
        self.body = body
        self.name = name
        self.assets = assets.compactMap(Asset.init)
    }
}

/// GitHub client error.
///
/// - sessionError: when URLSession throws an error.
/// - missingData: when the request doesn't return any data.
/// - decodingError: when there's an error decoding the API response.
enum GitHubClientError: FatalError {
    case sessionError(Error)
    case missingData
    case decodingError(Error)

    var errorDescription: String {
        switch self {
        case let .sessionError(error):
            return "Session error: \(error.localizedDescription)."
        case .missingData:
            return "No data received from the GitHub API."
        case let .decodingError(error):
            return "Error decoding JSON from API: \(error.localizedDescription)"
        }
    }
}

/// GitHub Client.
class GitHubClient: GitHubClienting {
    private static let releasesRepository: String = "xcode-project-manager/releases"

    /// Session.
    private let session: URLSession

    /// Base url.
    private let baseURL: URL = URL(string: "https://api.github.com")!

    /// Initializes the client with the session.
    ///
    /// - Parameter session: url session.
    init(session: URLSession = URLSession.shared) {
        self.session = session
    }

    /// Returns the list of available releases.
    ///
    /// - Returns: xpm releases.
    func releases() throws -> [Release] {
        let response = try request(path: "/repos/\(GitHubClient.releasesRepository)/releases")
        guard let releases = response as? [[String: Any]] else { return [] }
        return releases.compactMap(Release.init)
    }

    /// Executes a request against the GitHub API.
    ///
    /// - Parameters:
    ///   - path: request path.
    ///   - method: request HTTP method.
    /// - Returns: API json response.
    /// - Throws: if the request fails.
    fileprivate func request(path: String, method _: String = "GET") throws -> Any {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        var data: Data?
        var error: Error?
        let semaphore = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { _data, _, _error in
            data = _data
            error = _error
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 3)
        if let error = error {
            throw GitHubClientError.sessionError(error)
        } else if data == nil {
            throw GitHubClientError.missingData
        } else {
            do {
                return try JSONSerialization.jsonObject(with: data!, options: [])
            } catch {
                throw GitHubClientError.decodingError(error)
            }
        }
    }
}
