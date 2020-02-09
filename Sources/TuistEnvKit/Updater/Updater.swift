import Foundation
import TuistSupport

protocol Updating: AnyObject {
    func update(force: Bool) throws
}

final class Updater: Updating {
    // MARK: - Attributes

    let githubClient: GitHubClienting
    let versionsController: VersionsControlling
    let installer: Installing
    let envUpdater: EnvUpdating

    // MARK: - Init

    init(githubClient: GitHubClienting = GitHubClient(),
         versionsController: VersionsControlling = VersionsController(),
         installer: Installing = Installer(),
         envUpdater: EnvUpdating = EnvUpdater()) {
        self.githubClient = githubClient
        self.versionsController = versionsController
        self.installer = installer
        self.envUpdater = envUpdater
    }

    // MARK: - Internal

    func update(force: Bool) throws {
        let releases = try githubClient.releases()

        defer {
            try? self.envUpdater.update()
        }

        guard let highestRemoteVersion = releases.map({ $0.version }).sorted().last else {
            logger.info("No remote versions found")
            return
        }

        if force {
            logger.info("Forcing the update of version \(highestRemoteVersion)")
            try installer.install(version: highestRemoteVersion.description, force: true)
        } else if let highestLocalVersion = versionsController.semverVersions().sorted().last {
            if highestRemoteVersion <= highestLocalVersion {
                logger.info("There are no updates available")
            } else {
                logger.info("Installing new version available \(highestRemoteVersion)")
                try installer.install(version: highestRemoteVersion.description, force: false)
            }
        } else {
            logger.info("No local versions available. Installing the latest version \(highestRemoteVersion)")
            try installer.install(version: highestRemoteVersion.description, force: false)
        }
    }
}
