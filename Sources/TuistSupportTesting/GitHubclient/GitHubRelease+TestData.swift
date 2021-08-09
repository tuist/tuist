import Foundation
import struct TSCUtility.Version
import TuistSupport

public extension GitHubRelease {
    static func test(name: String = "1.2.3",
                     tagName: Version? = "1.2.3",
                     draft: Bool = false,
                     prerelease: Bool = false,
                     assets: [GitHubReleaseAsset] = []) -> GitHubRelease
    {
        return GitHubRelease(
            name: name,
            tagName: tagName,
            draft: draft,
            prerelease: prerelease,
            assets: assets
        )
    }
}
