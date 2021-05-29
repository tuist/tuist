import Foundation
import RxBlocking
import TuistSupport

protocol Updating: AnyObject {
    func update() throws
}

final class Updater: Updating {
    // MARK: - Attributes

    let versionsController: VersionsControlling
    let googleCloudStorageClient: GoogleCloudStorageClienting
    let installer: Installing
    let envUpdater: EnvUpdating

    // MARK: - Init

    init(versionsController: VersionsControlling = VersionsController(),
         installer: Installing = Installer(),
         envUpdater: EnvUpdating = EnvUpdater(),
         googleCloudStorageClient: GoogleCloudStorageClienting = GoogleCloudStorageClient())
    {
        self.versionsController = versionsController
        self.installer = installer
        self.envUpdater = envUpdater
        self.googleCloudStorageClient = googleCloudStorageClient
    }

    // MARK: - Internal

    func update() throws {
        defer {
            logger.info("Updating tuistenv", metadata: .section)
            try? self.envUpdater.update()
        }

        guard let highestRemoteVersion = try googleCloudStorageClient.latestVersion().toBlocking().first() else {
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
