import Foundation

protocol UpdatesControlling: AnyObject {
    func check() throws -> Release?
}

class UpdatesController: UpdatesControlling {
    static let lastTimeKey: String = "com.xcodepm.xpmenv.lastTimeChecked"

    /// GitHub client.
    let client: GitHubClienting

    /// Local versions controller.
    let localVersionsController: LocalVersionsControlling

    /// User defaults.
    let userDefaults: UserDefaults = UserDefaults.standard

    init(client: GitHubClient,
         localVersionsController: LocalVersionsControlling) {
        self.client = client
        self.localVersionsController = localVersionsController
    }

    /// If there's a new version to be installed, it returns its release.
    ///
    /// - Returns: new release to be installed.
    /// - Throws: an error if fetching the remote versions fails
    func check() throws -> Release? {
        let lastTimeTimestamp = userDefaults.double(forKey: UpdatesController.lastTimeKey)
        let lastTime = Date(timeIntervalSince1970: lastTimeTimestamp)
        let localVersions = localVersionsController.versions().sorted()

        /// Returns if there are local versions and the time past since the last check
        /// is less than 24 hours.
        if localVersions.count != 0 && Date().timeIntervalSince(lastTime) < 60 * 60 * 24 {
            return nil
        }

        defer {
            userDefaults.set(Date().timeIntervalSince1970, forKey: UpdatesController.lastTimeKey)
            userDefaults.synchronize()
        }

        guard let highestRemoteRelease = try client.releases().sorted(by: { $0.version < $1.version }).last,
            let highestLocalVersion = localVersions.last else {
            return nil
        }
        return (highestRemoteRelease.version > highestLocalVersion) ? highestRemoteRelease : nil
    }
}
