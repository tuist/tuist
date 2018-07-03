import Foundation
import Utility

/// GitHub release.
struct Release {
    /// Release asset.
    struct Asset {
        let downloadURL: Foundation.URL

        init?(json: [String: Any]) {
            guard let downloadURLString = json["browser_download_url"] as? String else { return nil }
            downloadURL = URL(string: downloadURLString)!
        }
    }

    // MARK: - Attributes

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
