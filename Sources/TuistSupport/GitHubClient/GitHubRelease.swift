import Foundation
import struct TSCUtility.Version

public struct GitHubRelease: Decodable {
    /// Release name.
    public let name: String

    /// Release tag name.
    public let tagName: Version

    /// Whether the release is a draft.
    public let draft: Bool

    /// Whether the release is a prerelease
    public let prerelease: Bool

    /// Release assets
    public let assets: [GitHubReleaseAsset]

    private enum CodingKeys: String, CodingKey {
        case name
        case tagName = "tag_name"
        case draft
        case prerelease
        case assets
    }

    /// Returns a resource to get the latest release of the given repository.
    /// - Parameter repositoryFullName: Repository full name (e.g. tuist/tuist)
    /// - Returns: Resource to get the latest release.
    public static func latest(repositoryFullName: String) -> HTTPResource<GitHubRelease, GitHubError> {
        return HTTPResource.jsonResource {
            var components = URLComponents(string: Constants.githubAPIURL)!
            components.path = "/repos/\(repositoryFullName)/releases/latest"
            var request = URLRequest(url: components.url!)
            request.httpMethod = "GET"
            return request
        }
    }
}
