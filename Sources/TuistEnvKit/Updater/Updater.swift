import Foundation
import RxBlocking
import TuistSupport

protocol Updating: AnyObject {
    func update() throws
}

final class Updater: Updating {
    // MARK: - Attributes

    let versionsController: VersionsControlling
    let installer: Installing
    let envUpdater: EnvUpdating
    let githubClient: GitHubClienting

    // MARK: - Init

    init(versionsController: VersionsControlling = VersionsController(),
         installer: Installing = Installer(),
         envUpdater: EnvUpdating = EnvUpdater(),
         githubClient: GitHubClienting = GitHubClient())
    {
        self.versionsController = versionsController
        self.installer = installer
        self.envUpdater = envUpdater
        self.githubClient = githubClient
    }

    // MARK: - Internal

    func update() throws {
        defer {
            logger.info("Updating tuistenv", metadata: .section)
            try? self.envUpdater.update()
        }
        let resource = GitHubRelease.latest(repositoryFullName: Constants.githubSlug)
        guard let highestRemoteVersion = try githubClient.dispatch(resource: resource).toBlocking().first?.object.tagName else {
            logger.warning("No remote versions found")
            return
        }

        if let highestLocalVersion = versionsController.semverVersions().sorted().last {
            if highestRemoteVersion <= highestLocalVersion {
                logger.notice("There are no updates available")
            } else {
                logger.notice("Installing new version available \(highestRemoteVersion)")
                try installer.install(version: highestRemoteVersion.description)
            }
        } else {
            logger.notice("No local versions available. Installing the latest version \(highestRemoteVersion)")
            try installer.install(version: highestRemoteVersion.description)
        }
    }
}
