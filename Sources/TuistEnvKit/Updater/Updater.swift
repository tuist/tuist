import Foundation

/// Objects that conform this interface expose an interface for checking
/// updates of tuist and installing them.
protocol Updating: AnyObject {
    /// Checks if there's a new version available. If there is it installs it locally.
    ///
    /// - Throws: an error if the releases cannot be fetched from GitHub or the installation
    /// process fails for any reason.
    func update() throws
}

final class Updater: Updating {
    /// GitHub client.
    let githubClient: GitHubClienting

    /// GitHub request factory.
    let githubRequestFactory: GitHubRequestsFactory = GitHubRequestsFactory()

    /// Versions controller.
    let versionsController: VersionsControlling

    /// Installer.
    let installer: Installing

    /// Initializes the updater with its attributes.
    ///
    /// - Parameters:
    ///   - githubClient: GitHub API client.
    ///   - versionsController: versions controller.
    ///   - installer: installer.
    init(githubClient: GitHubClienting = GitHubClient(),
         versionsController: VersionsControlling = VersionsController(),
         installer: Installing = Installer()) {
        self.githubClient = githubClient
        self.versionsController = versionsController
        self.installer = installer
    }

    /// Checks if there's a new version available. If there is it installs it locally.
    ///
    /// - Throws: an error if the releases cannot be fetched from GitHub or the installation
    /// process fails for any reason.
    func update() throws {
        let json = try githubClient.execute(request: githubRequestFactory.releases())
        let jsonDecoder = JSONDecoder()
        let jsonData = try JSONSerialization.data(withJSONObject: json, options: [])

        let releases: [Release] = try jsonDecoder.decode([Release].self, from: jsonData)

        guard let highestRemoteVersion = releases.map({ $0.version }).sorted().last,
            let highestLocalVersion = versionsController.semverVersions().sorted().last else {
            return
        }
        if highestRemoteVersion <= highestLocalVersion { return }

        try installer.install(version: highestRemoteVersion.description)
    }
}
