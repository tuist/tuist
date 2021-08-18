import Foundation
import TuistSupport

public extension GitHubReleaseAsset {
    static func test(name: String = "tuist.zip",
                     browserDownloadUrl: URL = URL(string: "https://download.tuist.io/tuist.zip")!) -> GitHubReleaseAsset
    {
        return GitHubReleaseAsset(
            name: name,
            browserDownloadUrl: browserDownloadUrl
        )
    }
}
